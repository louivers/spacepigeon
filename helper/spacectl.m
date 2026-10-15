// spacectl - small helper that lets SpacePigeon move windows between
// Spaces and switch Spaces instantly, with SIP fully enabled.
//
// The window-management calls are taken from yabai
// (https://github.com/asmvik/yabai), Copyright (c) 2019 Asmund Vikane,
// MIT License, and from ferry (https://github.com/softmaxe/ferry),
// Copyright (c) 2026 softmaxe, MIT License.
//
//   move:   SkyLight's bridged "move windows to managed space" operation
//           (works with SIP on since macOS 26.4).
//   focus:  synthesized high-velocity Dock swipe gestures (no Mission Control,
//           no animation), the technique yabai uses with SIP on.
//
// These are private macOS interfaces. A macOS update can break them; every
// command verifies its result and exits non-zero when it did not work, so the
// Lua side can fall back to the old behaviour.
//
// Exit codes: 0 ok, 1 failed, 2 bad usage, 3 not supported on this macOS.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define SPACECTL_VERSION "1.1.0"

#define SPACE_TYPE_USER       0
#define SPACE_TYPE_FULLSCREEN 4

#define SKYLIGHT_PATH "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
#define BRIDGED_OPERATION_SYMBOL "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
#define BRIDGED_MOVE_CLASS "SLSBridgedMoveWindowsToManagedSpaceOperation"

extern int SLSMainConnectionID(void);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int cid);
extern int SLSSpaceGetType(int cid, uint64_t sid);
extern CFArrayRef SLSCopySpacesForWindows(int cid, int selector, CFArrayRef window_list);
extern CFStringRef SLSCopyManagedDisplayForSpace(int cid, uint64_t sid);
extern uint64_t SLSManagedDisplayGetCurrentSpace(int cid, CFStringRef display);
extern CGError SLSSpaceSetFrontPSN(int cid, uint64_t sid, ProcessSerialNumber psn);
extern CGError SLSGetWindowOwner(int cid, uint32_t wid, int *wcid);
extern CGError SLSGetConnectionPSN(int cid, ProcessSerialNumber *psn);

typedef int64_t (*bridged_operation_fn)(void *operation);

static int g_cid;

static void fail(int code, const char *fmt, ...) __attribute__((noreturn, format(printf, 2, 3)));
static void fail(int code, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    fputs("spacectl: ", stderr);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);
    va_end(args);
    exit(code);
}

static uint64_t now_ns(void)
{
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static double elapsed_ms(uint64_t start_ns)
{
    return (now_ns() - start_ns) / 1e6;
}

static void sleep_ms(double ms)
{
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, ms / 1000.0, true);
}

// The window server ignores the bridged move from processes that have not
// loaded AppKit. Referencing an AppKit class keeps the framework linked and
// loaded even if the linker would otherwise drop it.
static void ensure_appkit_loaded(void)
{
    (void) [NSWorkspace class];
}

//
// Symbol lookup for functions that SkyLight does not export
// (yabai: misc/macho_dlsym.h, via ferry).
//

static struct mach_header_64 *macho_find_image_header(const char *target_name, intptr_t *slide)
{
    uint32_t image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; ++i) {
        const char *image_name = _dyld_get_image_name(i);
        if (image_name && strcmp(image_name, target_name) == 0) {
            *slide = _dyld_get_image_vmaddr_slide(i);
            return (struct mach_header_64 *) _dyld_get_image_header(i);
        }
    }
    return NULL;
}

static void *macho_find_symbol(const char *target_image, const char *target_symbol)
{
    intptr_t slide = 0;
    struct mach_header_64 *header = macho_find_image_header(target_image, &slide);
    if (!header) return NULL;

    struct segment_command_64 *linkedit = NULL;
    struct symtab_command *symtab = NULL;
    uint8_t *cursor = (uint8_t *) header + sizeof(struct mach_header_64);

    for (uint32_t i = 0; i < header->ncmds; ++i) {
        struct load_command *cmd = (struct load_command *) cursor;
        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *segment = (struct segment_command_64 *) cmd;
            if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) {
                linkedit = segment;
            }
        } else if (cmd->cmd == LC_SYMTAB) {
            symtab = (struct symtab_command *) cmd;
        }
        cursor += cmd->cmdsize;
    }

    if (!linkedit || !symtab) return NULL;

    uint8_t *linkedit_base = (uint8_t *) (linkedit->vmaddr - linkedit->fileoff + slide);
    const char *strings = (const char *) (linkedit_base + symtab->stroff);
    struct nlist_64 *symbols = (struct nlist_64 *) (linkedit_base + symtab->symoff);

    for (uint32_t i = 0; i < symtab->nsyms; ++i) {
        if (strcmp(strings + symbols[i].n_un.n_strx, target_symbol) == 0) {
            return (void *) (symbols[i].n_value + slide);
        }
    }

    return NULL;
}

static bridged_operation_fn find_bridged_perform(void)
{
    static bool looked = false;
    static bridged_operation_fn perform = NULL;
    if (!looked) {
        looked = true;
        if (objc_getClass(BRIDGED_MOVE_CLASS)) {
            perform = (bridged_operation_fn) macho_find_symbol(SKYLIGHT_PATH, BRIDGED_OPERATION_SYMBOL);
        }
    }
    return perform;
}

//
// Spaces.
//

static uint64_t cfnumber_u64(CFTypeRef value)
{
    uint64_t result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef) value, kCFNumberSInt64Type, &result);
    }
    return result;
}

static void cfstring_to_buf(CFStringRef string, char *buf, size_t size)
{
    buf[0] = '\0';
    if (string) CFStringGetCString(string, buf, (CFIndex) size, kCFStringEncodingUTF8);
}

// Returns the 0-based position of `sid` within its display's space list and
// the number of spaces on that display, or -1 when the space is unknown.
static int space_index_on_display(uint64_t sid, int *count_out)
{
    CFArrayRef displays = SLSCopyManagedDisplaySpaces(g_cid);
    if (!displays) return -1;

    int result = -1;
    for (CFIndex i = 0; i < CFArrayGetCount(displays) && result < 0; ++i) {
        CFDictionaryRef display = CFArrayGetValueAtIndex(displays, i);
        CFArrayRef spaces = CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (!spaces) continue;

        CFIndex count = CFArrayGetCount(spaces);
        for (CFIndex j = 0; j < count; ++j) {
            CFDictionaryRef space = CFArrayGetValueAtIndex(spaces, j);
            if (cfnumber_u64(CFDictionaryGetValue(space, CFSTR("id64"))) == sid) {
                result = (int) j;
                if (count_out) *count_out = (int) count;
                break;
            }
        }
    }

    CFRelease(displays);
    return result;
}

static CFArrayRef window_id_array(uint32_t wid)
{
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &wid);
    CFArrayRef array = CFArrayCreate(NULL, (const void **) &number, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);
    return array;
}

// Space ids the window is on (0x7 = all space types).
static int window_spaces(uint32_t wid, uint64_t *out, int max)
{
    CFArrayRef windows = window_id_array(wid);
    CFArrayRef spaces = SLSCopySpacesForWindows(g_cid, 0x7, windows);
    CFRelease(windows);
    if (!spaces) return 0;

    int n = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(spaces) && n < max; ++i) {
        out[n++] = cfnumber_u64(CFArrayGetValueAtIndex(spaces, i));
    }
    CFRelease(spaces);
    return n;
}

static bool window_is_on_space(uint32_t wid, uint64_t sid)
{
    uint64_t spaces[16];
    int n = window_spaces(wid, spaces, 16);
    for (int i = 0; i < n; ++i) {
        if (spaces[i] == sid) return true;
    }
    return false;
}

//
// Displays and the cursor.
//

static CGDirectDisplayID display_id_for_uuid(CFStringRef uuid)
{
    if (!uuid) return 0;
    if (CFEqual(uuid, CFSTR("Main"))) return CGMainDisplayID();

    uint32_t count = 0;
    CGDirectDisplayID ids[32];
    if (CGGetActiveDisplayList(32, ids, &count) != kCGErrorSuccess) return 0;

    for (uint32_t i = 0; i < count; ++i) {
        CFUUIDRef display_uuid = CGDisplayCreateUUIDFromDisplayID(ids[i]);
        if (!display_uuid) continue;
        CFStringRef string = CFUUIDCreateString(NULL, display_uuid);
        CFRelease(display_uuid);
        bool match = string && CFStringCompare(string, uuid, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
        if (string) CFRelease(string);
        if (match) return ids[i];
    }

    return 0;
}

static CGDirectDisplayID display_under_cursor(void)
{
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return 0;
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);

    uint32_t count = 0;
    CGDirectDisplayID display = 0;
    CGGetDisplaysWithPoint(point, 1, &display, &count);
    return count ? display : 0;
}

//
// Commands.
//

static int cmd_check(void)
{
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    bool move = find_bridged_perform() != NULL;
    printf("{\"version\":\"%s\",\"macos\":\"%ld.%ld.%ld\",\"move\":%s,\"focus\":true}\n",
           SPACECTL_VERSION, (long) v.majorVersion, (long) v.minorVersion, (long) v.patchVersion,
           move ? "true" : "false");
    return move ? 0 : 3;
}

static int cmd_spaces(void)
{
    CFArrayRef displays = SLSCopyManagedDisplaySpaces(g_cid);
    if (!displays) fail(1, "could not read spaces");

    printf("[");
    for (CFIndex i = 0; i < CFArrayGetCount(displays); ++i) {
        CFDictionaryRef display = CFArrayGetValueAtIndex(displays, i);
        char uuid[128];
        CFStringRef display_id = CFDictionaryGetValue(display, CFSTR("Display Identifier"));
        cfstring_to_buf(display_id, uuid, sizeof(uuid));
        uint64_t current = display_id ? SLSManagedDisplayGetCurrentSpace(g_cid, display_id) : 0;

        printf("%s{\"display\":\"%s\",\"current\":%llu,\"spaces\":[", i ? "," : "", uuid, (unsigned long long) current);
        CFArrayRef spaces = CFDictionaryGetValue(display, CFSTR("Spaces"));
        CFIndex count = spaces ? CFArrayGetCount(spaces) : 0;
        for (CFIndex j = 0; j < count; ++j) {
            CFDictionaryRef space = CFArrayGetValueAtIndex(spaces, j);
            uint64_t sid = cfnumber_u64(CFDictionaryGetValue(space, CFSTR("id64")));
            printf("%s{\"id\":%llu,\"type\":%d}", j ? "," : "", (unsigned long long) sid, SLSSpaceGetType(g_cid, sid));
        }
        printf("]}");
    }
    printf("]\n");

    CFRelease(displays);
    return 0;
}

// Standard-looking windows on any Space, front to back, for one process or
// (pid 0) for all processes. Works for windows on inactive Spaces, where
// Accessibility often cannot see them.
static int cmd_windows(pid_t pid)
{
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!list) fail(1, "could not read window list");

    printf("[");
    int printed = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(list); ++i) {
        CFDictionaryRef info = CFArrayGetValueAtIndex(list, i);
        int owner = 0, layer = -1;
        uint32_t wid = 0;
        CFNumberRef owner_ref = CFDictionaryGetValue(info, kCGWindowOwnerPID);
        CFNumberRef layer_ref = CFDictionaryGetValue(info, kCGWindowLayer);
        CFNumberRef wid_ref = CFDictionaryGetValue(info, kCGWindowNumber);
        if (!owner_ref || !layer_ref || !wid_ref) continue;
        CFNumberGetValue(owner_ref, kCFNumberIntType, &owner);
        CFNumberGetValue(layer_ref, kCFNumberIntType, &layer);
        CFNumberGetValue(wid_ref, kCFNumberSInt32Type, &wid);
        if ((pid && owner != pid) || layer != 0 || !wid) continue;

        CGRect bounds = CGRectZero;
        CFDictionaryRef bounds_ref = CFDictionaryGetValue(info, kCGWindowBounds);
        if (!bounds_ref || !CGRectMakeWithDictionaryRepresentation(bounds_ref, &bounds)) continue;
        if (bounds.size.width < 100 || bounds.size.height < 100) continue;

        uint64_t spaces[16];
        int n = window_spaces(wid, spaces, 16);
        if (n == 0) continue; // minimized, hidden or not a managed window

        printf("%s{\"id\":%u,\"pid\":%d,\"spaces\":[", printed++ ? "," : "", wid, owner);
        for (int s = 0; s < n; ++s) {
            printf("%s%llu", s ? "," : "", (unsigned long long) spaces[s]);
        }
        printf("],\"fullscreen\":%s,\"w\":%d,\"h\":%d}",
               SLSSpaceGetType(g_cid, spaces[0]) == SPACE_TYPE_FULLSCREEN ? "true" : "false",
               (int) bounds.size.width, (int) bounds.size.height);
    }
    printf("]\n");

    CFRelease(list);
    return 0;
}

// Moves one window and waits until the window server reports it on the target.
// Returns 0 on success, 1 when it did not arrive, 3 when unsupported.
static int move_window(uint32_t wid, uint64_t sid, int timeout_ms, double *took_ms)
{
    bridged_operation_fn perform = find_bridged_perform();
    if (!perform) return 3;

    if (window_is_on_space(wid, sid)) {
        if (took_ms) *took_ms = 0;
        return 0;
    }

    int owner_cid = 0;
    ProcessSerialNumber psn = {0};
    bool have_psn = SLSGetWindowOwner(g_cid, wid, &owner_cid) == kCGErrorSuccess &&
                    SLSGetConnectionPSN(owner_cid, &psn) == kCGErrorSuccess;

    uint64_t start = now_ns();
    Class cls = objc_getClass(BRIDGED_MOVE_CLASS);
    CFArrayRef windows = window_id_array(wid);
    SEL sel = sel_registerName("initWithWindows:spaceID:");
    id operation = ((id (*)(id, SEL, id, uint64_t)) objc_msgSend)([cls alloc], sel, (id) windows, sid);
    perform(operation);
    [operation release];
    CFRelease(windows);

    if (have_psn) SLSSpaceSetFrontPSN(g_cid, sid, psn);

    // The operation is asynchronous: poll until the window server agrees.
    bool moved = false;
    while (!(moved = window_is_on_space(wid, sid)) && elapsed_ms(start) < timeout_ms) {
        sleep_ms(2);
    }

    if (took_ms) *took_ms = elapsed_ms(start);
    return moved ? 0 : 1;
}

static int cmd_move(uint32_t wid, uint64_t sid, int timeout_ms)
{
    int owner_cid = 0;
    if (SLSGetWindowOwner(g_cid, wid, &owner_cid) != kCGErrorSuccess) fail(1, "window %u not found", wid);
    if (space_index_on_display(sid, NULL) < 0) fail(1, "space %llu not found", (unsigned long long) sid);
    if (SLSSpaceGetType(g_cid, sid) == SPACE_TYPE_FULLSCREEN) fail(2, "space %llu is a fullscreen space", (unsigned long long) sid);

    double took = 0;
    int result = move_window(wid, sid, timeout_ms, &took);
    if (result == 3) fail(3, "bridged move operation not available on this macOS");
    if (result != 0) fail(1, "window %u did not reach space %llu within %d ms", wid, (unsigned long long) sid, timeout_ms);

    printf("{\"moved\":true,\"window\":%u,\"space\":%llu,\"ms\":%.1f}\n", wid, (unsigned long long) sid, took);
    return 0;
}

// yabai: space_manager_focus_space_using_gesture. Posts one high-velocity
// Dock swipe per Space to skip over, which switches without the animation.
static void post_space_swipes(int steps)
{
    if (steps == 0) return;

    CGEventRef event = CGEventCreate(NULL);
    if (!event) return;

    double sign = steps > 0 ? 1.0 : -1.0;
    CGEventSetIntegerValueField(event, 55, 30);   // kCGSEventTypeField = kCGSEventDockControl
    CGEventSetIntegerValueField(event, 110, 23);  // kCGEventGestureHIDType = kIOHIDEventTypeDockSwipe
    CGEventSetIntegerValueField(event, 123, 1);   // kCGEventGestureSwipeMotion = horizontal
    CGEventSetDoubleValueField(event, 124, sign); // kCGEventGestureSwipeProgress
    CGEventSetDoubleValueField(event, 129, sign * 9999.0); // kCGEventGestureSwipeVelocityX

    int count = abs(steps);
    for (int i = 0; i < count; ++i) {
        CGEventSetIntegerValueField(event, 132, 1); // kCGEventGesturePhase = began
        CGEventPost(kCGSessionEventTap, event);
        CGEventSetIntegerValueField(event, 132, 4); // kCGEventGesturePhase = ended
        CGEventPost(kCGSessionEventTap, event);
    }

    CFRelease(event);
}

static int cmd_focus(uint64_t sid, int timeout_ms)
{
    CFStringRef display = SLSCopyManagedDisplayForSpace(g_cid, sid);
    if (!display) fail(1, "space %llu not found", (unsigned long long) sid);

    uint64_t start = now_ns();
    uint64_t current = SLSManagedDisplayGetCurrentSpace(g_cid, display);
    if (current == sid) {
        CFRelease(display);
        printf("{\"focused\":true,\"space\":%llu,\"ms\":0}\n", (unsigned long long) sid);
        return 0;
    }

    int cur_index = space_index_on_display(current, NULL);
    int new_index = space_index_on_display(sid, NULL);
    if (cur_index < 0 || new_index < 0) {
        CFRelease(display);
        fail(1, "could not place spaces %llu and %llu on their display", (unsigned long long) current, (unsigned long long) sid);
    }

    // The swipe acts on the display under the cursor.
    CGDirectDisplayID target = display_id_for_uuid(display);
    if (target && display_under_cursor() != target) {
        CGRect bounds = CGDisplayBounds(target);
        CGWarpMouseCursorPosition(CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)));
        sleep_ms(10);
    }

    post_space_swipes(new_index - cur_index);

    bool done = false;
    while (!(done = SLSManagedDisplayGetCurrentSpace(g_cid, display) == sid) && elapsed_ms(start) < timeout_ms) {
        sleep_ms(5);
    }
    CFRelease(display);

    if (!done) fail(1, "space %llu did not become active within %d ms", (unsigned long long) sid, timeout_ms);
    printf("{\"focused\":true,\"space\":%llu,\"ms\":%.1f}\n", (unsigned long long) sid, elapsed_ms(start));
    return 0;
}

// Moves a window of the frontmost app to another desktop on the same display
// and back, verifying both moves. Proves the bridged move works on this Mac.
static int cmd_selftest(void)
{
    printf("spacectl %s self test\n", SPACECTL_VERSION);
    if (!find_bridged_perform()) {
        printf("FAIL: bridged move operation not found on this macOS\n");
        return 3;
    }
    printf("ok:   bridged move operation found\n");

    pid_t pid = [[[NSWorkspace sharedWorkspace] frontmostApplication] processIdentifier];
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    uint32_t wid = 0;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list) && !wid; ++i) {
        CFDictionaryRef info = CFArrayGetValueAtIndex(list, i);
        CFNumberRef owner_ref = CFDictionaryGetValue(info, kCGWindowOwnerPID);
        CFNumberRef layer_ref = CFDictionaryGetValue(info, kCGWindowLayer);
        CFNumberRef wid_ref = CFDictionaryGetValue(info, kCGWindowNumber);
        if (!owner_ref || !layer_ref || !wid_ref) continue;
        int owner = 0, layer = -1;
        CFNumberGetValue(owner_ref, kCFNumberIntType, &owner);
        CFNumberGetValue(layer_ref, kCFNumberIntType, &layer);
        if (owner == pid && layer == 0) {
            CFNumberGetValue(wid_ref, kCFNumberSInt32Type, &wid);
        }
    }
    if (list) CFRelease(list);
    if (!wid) {
        printf("FAIL: no window found for the frontmost app (pid %d)\n", pid);
        return 1;
    }

    uint64_t spaces[16];
    if (window_spaces(wid, spaces, 16) < 1) {
        printf("FAIL: window %u is not on a Space\n", wid);
        return 1;
    }
    uint64_t home = spaces[0];
    if (SLSSpaceGetType(g_cid, home) != SPACE_TYPE_USER) {
        printf("FAIL: run this from a normal desktop, not a fullscreen app\n");
        return 1;
    }

    // Find another desktop on the same display.
    uint64_t other = 0;
    CFArrayRef displays = SLSCopyManagedDisplaySpaces(g_cid);
    for (CFIndex i = 0; displays && i < CFArrayGetCount(displays) && !other; ++i) {
        CFArrayRef display_spaces = CFDictionaryGetValue(CFArrayGetValueAtIndex(displays, i), CFSTR("Spaces"));
        if (!display_spaces) continue;
        bool home_here = false;
        uint64_t candidate = 0;
        for (CFIndex j = 0; j < CFArrayGetCount(display_spaces); ++j) {
            uint64_t sid = cfnumber_u64(CFDictionaryGetValue(CFArrayGetValueAtIndex(display_spaces, j), CFSTR("id64")));
            if (sid == home) home_here = true;
            else if (!candidate && SLSSpaceGetType(g_cid, sid) == SPACE_TYPE_USER) candidate = sid;
        }
        if (home_here) other = candidate;
    }
    if (displays) CFRelease(displays);
    if (!other) {
        printf("FAIL: need at least two desktops on this display\n");
        return 1;
    }

    printf("info: moving window %u from space %llu to %llu and back\n", wid, (unsigned long long) home, (unsigned long long) other);

    double away_ms = 0, back_ms = 0;
    int away = move_window(wid, other, 1500, &away_ms);
    printf("%s move away (%.1f ms)\n", away == 0 ? "ok:  " : "FAIL:", away_ms);
    int back = move_window(wid, home, 1500, &back_ms);
    printf("%s move back (%.1f ms)\n", back == 0 ? "ok:  " : "FAIL:", back_ms);

    bool pass = away == 0 && back == 0;
    printf(pass ? "PASS: window moves work on this Mac\n" : "FAIL: window moves do not work on this Mac\n");
    return pass ? 0 : 1;
}

// Lists SkyLight's bridged operations and their selectors. Read only; used to
// explore whether Space reordering (for fullscreen apps) is reachable.
static int cmd_probe(void)
{
    printf("bridged move operation: %s\n", find_bridged_perform() ? "found" : "missing");

    unsigned int class_count = 0;
    Class *classes = objc_copyClassList(&class_count);
    for (unsigned int i = 0; i < class_count; ++i) {
        const char *name = class_getName(classes[i]);
        if (strncmp(name, "SLSBridged", 10) != 0) continue;

        printf("\n%s\n", name);
        unsigned int method_count = 0;
        Method *methods = class_copyMethodList(classes[i], &method_count);
        for (unsigned int m = 0; m < method_count; ++m) {
            printf("  - %s\n", sel_getName(method_getName(methods[m])));
        }
        if (methods) free(methods);

        Method *class_methods = class_copyMethodList(object_getClass((id) classes[i]), &method_count);
        for (unsigned int m = 0; m < method_count; ++m) {
            printf("  + %s\n", sel_getName(method_getName(class_methods[m])));
        }
        if (class_methods) free(class_methods);
    }
    if (classes) free(classes);
    return 0;
}

static void usage(FILE *stream)
{
    fputs("usage: spacectl <command> [args]\n"
          "\n"
          "  check                       report what works on this macOS (JSON)\n"
          "  spaces                      list displays and their Spaces (JSON)\n"
          "  windows [pid]               list windows on any Space, all or one process (JSON)\n"
          "  move <window-id> <space-id> [timeout-ms]   move a window to a desktop\n"
          "  focus <space-id> [timeout-ms]              switch to a Space instantly\n"
          "  selftest                    move a window of the frontmost app away and back\n"
          "  probe                       list SkyLight bridged operations (read only)\n"
          "  version\n", stream);
}

static unsigned long long parse_u64(const char *text, const char *what)
{
    char *end = NULL;
    unsigned long long value = strtoull(text, &end, 10);
    if (!end || *end != '\0' || value == 0) fail(2, "invalid %s '%s'", what, text);
    return value;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        ensure_appkit_loaded();
        g_cid = SLSMainConnectionID();

        if (argc < 2) {
            usage(stderr);
            return 2;
        }

        const char *cmd = argv[1];
        if (strcmp(cmd, "check") == 0) return cmd_check();
        if (strcmp(cmd, "spaces") == 0) return cmd_spaces();
        if (strcmp(cmd, "selftest") == 0) return cmd_selftest();
        if (strcmp(cmd, "probe") == 0) return cmd_probe();
        if (strcmp(cmd, "version") == 0) { puts(SPACECTL_VERSION); return 0; }
        if (strcmp(cmd, "-h") == 0 || strcmp(cmd, "--help") == 0 || strcmp(cmd, "help") == 0) { usage(stdout); return 0; }

        if (strcmp(cmd, "windows") == 0 && argc == 2) {
            return cmd_windows(0);
        }
        if (strcmp(cmd, "windows") == 0 && argc == 3) {
            return cmd_windows((pid_t) parse_u64(argv[2], "pid"));
        }
        if (strcmp(cmd, "move") == 0 && (argc == 4 || argc == 5)) {
            int timeout = argc == 5 ? (int) parse_u64(argv[4], "timeout") : 1500;
            return cmd_move((uint32_t) parse_u64(argv[2], "window id"), parse_u64(argv[3], "space id"), timeout);
        }
        if (strcmp(cmd, "focus") == 0 && (argc == 3 || argc == 4)) {
            int timeout = argc == 4 ? (int) parse_u64(argv[3], "timeout") : 1500;
            return cmd_focus(parse_u64(argv[2], "space id"), timeout);
        }

        usage(stderr);
        return 2;
    }
}
