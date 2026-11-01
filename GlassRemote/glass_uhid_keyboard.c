/*
 * Glass Remote Virtual Keyboard
 *
 * Android ARM helper exposing a keyboard and consumer-control device through
 * /dev/uhid. Input protocol on stdin:
 *   K <USB HID keyboard usage>
 *   C <USB HID consumer usage>
 *
 * A single process and ADB shell stream stay open for low-latency key reports.
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

/* Report 1: keyboard; Report 2: Consumer Control. */
static const uint8_t report_descriptor[] = {
    0x05,0x01, 0x09,0x06, 0xA1,0x01, 0x85,0x01,
    0x05,0x07, 0x19,0xE0, 0x29,0xE7, 0x15,0x00,
    0x25,0x01, 0x75,0x01, 0x95,0x08, 0x81,0x02,
    0x95,0x01, 0x75,0x08, 0x81,0x01,
    0x95,0x06, 0x75,0x08, 0x15,0x00, 0x25,0x65,
    0x05,0x07, 0x19,0x00, 0x29,0x65, 0x81,0x00, 0xC0,
    0x05,0x0C, 0x09,0x01, 0xA1,0x01, 0x85,0x02,
    0x15,0x00, 0x26,0xFF,0x03, 0x19,0x00, 0x2A,0xFF,0x03,
    0x75,0x10, 0x95,0x01, 0x81,0x00, 0xC0
};

static int write_event(int fd, const struct uhid_event *event) {
    ssize_t n;
    do { n = write(fd, event, sizeof(*event)); } while (n < 0 && errno == EINTR);
    return n == (ssize_t)sizeof(*event) ? 0 : -1;
}

static int keyboard_report(int fd, uint8_t usage, int down) {
    struct uhid_event e;
    memset(&e, 0, sizeof(e));
    e.type = UHID_INPUT2;
    e.u.input2.size = 9;
    e.u.input2.data[0] = 1;
    if (down) e.u.input2.data[3] = usage;
    return write_event(fd, &e);
}

static int consumer_report(int fd, uint16_t usage, int down) {
    struct uhid_event e;
    memset(&e, 0, sizeof(e));
    e.type = UHID_INPUT2;
    e.u.input2.size = 3;
    e.u.input2.data[0] = 2;
    if (down) {
        e.u.input2.data[1] = (uint8_t)(usage & 0xff);
        e.u.input2.data[2] = (uint8_t)(usage >> 8);
    }
    return write_event(fd, &e);
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
    strncpy((char *)create.u.create2.name, "Glass Remote Virtual Keyboard",
            sizeof(create.u.create2.name) - 1);
    strncpy((char *)create.u.create2.phys, "glassremote/uhid-keyboard",
            sizeof(create.u.create2.phys) - 1);
    create.u.create2.rd_size = (uint16_t)sizeof(report_descriptor);
    create.u.create2.bus = BUS_USB;
    create.u.create2.vendor = 0x18D1;
    create.u.create2.product = 0x4EE7;
    create.u.create2.version = 1;
    memcpy(create.u.create2.rd_data, report_descriptor, sizeof(report_descriptor));

    if (write_event(fd, &create) < 0) {
        printf("ERROR UHID_CREATE2 write: %s\n", strerror(errno));
        fflush(stdout);
        close(fd);
        return 1;
    }

    puts("READY");
    fflush(stdout);

    char line[64];
    while (fgets(line, sizeof(line), stdin)) {
        char kind = 0;
        unsigned int value = 0;
        if (sscanf(line, " %c %u", &kind, &value) != 2) continue;

        int rc = 0;
        if (kind == 'K' && value > 0 && value <= 0x65) {
            rc = keyboard_report(fd, (uint8_t)value, 1);
            if (rc == 0) rc = keyboard_report(fd, (uint8_t)value, 0);
        } else if (kind == 'C' && value > 0 && value <= 0x03ff) {
            rc = consumer_report(fd, (uint16_t)value, 1);
            if (rc == 0) rc = consumer_report(fd, (uint16_t)value, 0);
        } else {
            continue;
        }

        if (rc < 0) {
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
