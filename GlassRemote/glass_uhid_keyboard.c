/*
 * Glass Remote Virtual Keyboard
 *
 * Android ARM helper exposing a keyboard and Consumer Control through /dev/uhid.
 * Persistent stdin protocol:
 *   K <USB HID keyboard usage>
 *   C <USB HID consumer usage>
 *
 * The helper creates one UHID device, prints READY, then stays alive and
 * processes remote-control reports until its stdin stream closes.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define UHID_DESTROY 1u
#define UHID_CREATE2 11u
#define UHID_INPUT2 12u
#define UHID_DATA_MAX 4096u
#define HID_MAX_DESCRIPTOR_SIZE 4096u
#define BUS_USB 0x03u

struct uhid_create2_req {
    uint8_t name[128];
    uint8_t phys[64];
    uint8_t uniq[64];
    uint16_t rd_size;
    uint16_t bus;
    uint32_t vendor;
    uint32_t product;
    uint32_t version;
    uint32_t country;
    uint8_t rd_data[HID_MAX_DESCRIPTOR_SIZE];
} __attribute__((packed));

struct uhid_input2_req {
    uint16_t size;
    uint8_t data[UHID_DATA_MAX];
} __attribute__((packed));

struct uhid_event {
    uint32_t type;
    union {
        struct uhid_create2_req create2;
        struct uhid_input2_req input2;
    } u;
} __attribute__((packed));

/*
 * Report ID 1: standard 8-byte boot-style keyboard report.
 * Report ID 2: 16-bit Consumer Control usage.
 */
static const uint8_t report_descriptor[] = {
    0x05, 0x01,       /* Usage Page (Generic Desktop) */
    0x09, 0x06,       /* Usage (Keyboard) */
    0xA1, 0x01,       /* Collection (Application) */
    0x85, 0x01,       /*   Report ID (1) */
    0x05, 0x07,       /*   Usage Page (Keyboard) */
    0x19, 0xE0,       /*   Usage Minimum (Left Control) */
    0x29, 0xE7,       /*   Usage Maximum (Right GUI) */
    0x15, 0x00,       /*   Logical Minimum (0) */
    0x25, 0x01,       /*   Logical Maximum (1) */
    0x75, 0x01,       /*   Report Size (1) */
    0x95, 0x08,       /*   Report Count (8) */
    0x81, 0x02,       /*   Input (Data, Variable, Absolute) */
    0x95, 0x01,       /*   Report Count (1) */
    0x75, 0x08,       /*   Report Size (8) */
    0x81, 0x01,       /*   Input (Constant) */
    0x95, 0x06,       /*   Report Count (6) */
    0x75, 0x08,       /*   Report Size (8) */
    0x15, 0x00,       /*   Logical Minimum (0) */
    0x25, 0x65,       /*   Logical Maximum (101) */
    0x05, 0x07,       /*   Usage Page (Keyboard) */
    0x19, 0x00,       /*   Usage Minimum (0) */
    0x29, 0x65,       /*   Usage Maximum (101) */
    0x81, 0x00,       /*   Input (Data, Array) */
    0xC0,             /* End Collection */

    0x05, 0x0C,       /* Usage Page (Consumer) */
    0x09, 0x01,       /* Usage (Consumer Control) */
    0xA1, 0x01,       /* Collection (Application) */
    0x85, 0x02,       /*   Report ID (2) */
    0x15, 0x00,       /*   Logical Minimum (0) */
    0x26, 0xFF, 0x03, /*   Logical Maximum (1023) */
    0x19, 0x00,       /*   Usage Minimum (0) */
    0x2A, 0xFF, 0x03, /*   Usage Maximum (1023) */
    0x75, 0x10,       /*   Report Size (16) */
    0x95, 0x01,       /*   Report Count (1) */
    0x81, 0x00,       /*   Input (Data, Array) */
    0xC0              /* End Collection */
};

static int write_event(int fd, const struct uhid_event *event) {
    ssize_t n;
    do {
        n = write(fd, event, sizeof(*event));
    } while (n < 0 && errno == EINTR);

    return n == (ssize_t)sizeof(*event) ? 0 : -1;
}

static int keyboard_report(int fd, uint8_t usage, int pressed) {
    struct uhid_event event;
    memset(&event, 0, sizeof(event));

    event.type = UHID_INPUT2;
    event.u.input2.size = 9;
    event.u.input2.data[0] = 1; /* Report ID */
    if (pressed) {
        event.u.input2.data[3] = usage; /* First key slot */
    }

    return write_event(fd, &event);
}

static int consumer_report(int fd, uint16_t usage, int pressed) {
    struct uhid_event event;
    memset(&event, 0, sizeof(event));

    event.type = UHID_INPUT2;
    event.u.input2.size = 3;
    event.u.input2.data[0] = 2; /* Report ID */

    if (pressed) {
        event.u.input2.data[1] = (uint8_t)(usage & 0xff);
        event.u.input2.data[2] = (uint8_t)(usage >> 8);
    }

    return write_event(fd, &event);
}

int main(void) {
    int fd = open("/dev/uhid", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        printf("ERROR open /dev/uhid: %s\n", strerror(errno));
        fflush(stdout);
        return 1;
    }

    struct uhid_event create;
    memset(&create, 0, sizeof(create));
    create.type = UHID_CREATE2;

    strncpy((char *)create.u.create2.name,
            "Glass Remote Virtual Keyboard",
            sizeof(create.u.create2.name) - 1);
    strncpy((char *)create.u.create2.phys,
            "glassremote/uhid-keyboard",
            sizeof(create.u.create2.phys) - 1);

    create.u.create2.rd_size = (uint16_t)sizeof(report_descriptor);
    create.u.create2.bus = BUS_USB;
    create.u.create2.vendor = 0x18D1;
    create.u.create2.product = 0x4EE7;
    create.u.create2.version = 1;

    memcpy(create.u.create2.rd_data, report_descriptor,
           sizeof(report_descriptor));

    if (write_event(fd, &create) < 0) {
        printf("ERROR UHID_CREATE2 write: %s\n", strerror(errno));
        fflush(stdout);
        close(fd);
        return 1;
    }

    puts("READY");
    fflush(stdout);

    char line[64];

    while (fgets(line, sizeof(line), stdin) != NULL) {
        char kind = '\0';
        unsigned int value = 0;

        if (sscanf(line, " %c %u", &kind, &value) != 2) {
            continue;
        }

        int result = 0;

        if (kind == 'K' && value > 0 && value <= 0x65) {
            result = keyboard_report(fd, (uint8_t)value, 1);
            if (result == 0) {
                result = keyboard_report(fd, (uint8_t)value, 0);
            }
        } else if (kind == 'C' && value > 0 && value <= 0x03ff) {
            result = consumer_report(fd, (uint16_t)value, 1);
            if (result == 0) {
                result = consumer_report(fd, (uint16_t)value, 0);
            }
        } else {
            continue;
        }

        if (result < 0) {
            printf("ERROR UHID_INPUT2 write: %s\n", strerror(errno));
            fflush(stdout);
            break;
        }
    }

    struct uhid_event destroy;
    memset(&destroy, 0, sizeof(destroy));
    destroy.type = UHID_DESTROY;
    (void)write_event(fd, &destroy);

    close(fd);
    return 0;
}
