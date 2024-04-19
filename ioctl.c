#include <stdio.h>
#include <linux/const.h>
#include <linux/ioctl.h>
#include <linux/types.h>



#define GPIO_MAX_NAME_SIZE 32
#define GPIO_V2_LINES_MAX 64
#define GPIO_V2_LINE_NUM_ATTRS_MAX 10


struct gpiochip_info {
	char name[GPIO_MAX_NAME_SIZE];
	char label[GPIO_MAX_NAME_SIZE];
	__u32 lines;
};

struct gpio_v2_line_attribute {
	__u32 id;
	__u32 padding;
	union {
		__aligned_u64 flags;
		__aligned_u64 values;
		__u32 debounce_period_us;
	};
};

struct gpio_v2_line_config_attribute {
	struct gpio_v2_line_attribute attr;
	__aligned_u64 mask;
};

struct gpio_v2_line_config {
	__aligned_u64 flags;
	__u32 num_attrs;
	/* Pad to fill implicit padding and reserve space for future use. */
	__u32 padding[5];
	struct gpio_v2_line_config_attribute attrs[GPIO_V2_LINE_NUM_ATTRS_MAX];
};

struct gpio_v2_line_request {
	__u32 offsets[GPIO_V2_LINES_MAX];
	char consumer[GPIO_MAX_NAME_SIZE];
	struct gpio_v2_line_config config;
	__u32 num_lines;
	__u32 event_buffer_size;
	/* Pad to fill implicit padding and reserve space for future use. */
	__u32 padding[5];
	__s32 fd;
};

struct gpio_v2_line_info {
	char name[GPIO_MAX_NAME_SIZE];
	char consumer[GPIO_MAX_NAME_SIZE];
	__u32 offset;
	__u32 num_attrs;
	__aligned_u64 flags;
	struct gpio_v2_line_attribute attrs[GPIO_V2_LINE_NUM_ATTRS_MAX];
	/* Space reserved for future use. */
	__u32 padding[4];
};
struct gpio_v2_line_values {
	__aligned_u64 bits;
	__aligned_u64 mask;
};


#define GPIO_GET_CHIPINFO_IOCTL _IOR(0xB4, 0x01, struct gpiochip_info)
#define GPIO_GET_LINEINFO_UNWATCH_IOCTL _IOWR(0xB4, 0x0C, __u32)

/*
 * v2 ioctl()s
 */
#define GPIO_V2_GET_LINEINFO_IOCTL _IOWR(0xB4, 0x05, struct gpio_v2_line_info)
#define GPIO_V2_GET_LINEINFO_WATCH_IOCTL _IOWR(0xB4, 0x06, struct gpio_v2_line_info)
#define GPIO_V2_GET_LINE_IOCTL _IOWR(0xB4, 0x07, struct gpio_v2_line_request)
#define GPIO_V2_LINE_SET_CONFIG_IOCTL _IOWR(0xB4, 0x0D, struct gpio_v2_line_config)
#define GPIO_V2_LINE_GET_VALUES_IOCTL _IOWR(0xB4, 0x0E, struct gpio_v2_line_values)
#define GPIO_V2_LINE_SET_VALUES_IOCTL _IOWR(0xB4, 0x0F, struct gpio_v2_line_values)


int main()
{
    printf( "0x%08X GPIO_GET_CHIPINFO_IOCTL\n", GPIO_GET_CHIPINFO_IOCTL );
    printf( "0x%08X GPIO_V2_GET_LINEINFO_IOCTL\n", GPIO_V2_GET_LINEINFO_IOCTL );
    printf( "0x%08X GPIO_V2_GET_LINEINFO_WATCH_IOCTL\n", GPIO_V2_GET_LINEINFO_WATCH_IOCTL );
    printf( "0x%08X GPIO_V2_GET_LINE_IOCTL\n", GPIO_V2_GET_LINE_IOCTL );
    printf( "0x%08X GPIO_GET_LINEINFO_UNWATCH_IOCTL\n", GPIO_GET_LINEINFO_UNWATCH_IOCTL );
    printf( "0x%08X GPIO_V2_LINE_SET_CONFIG_IOCTL\n", GPIO_V2_LINE_SET_CONFIG_IOCTL );
    printf( "0x%08X GPIO_V2_LINE_GET_VALUES_IOCTL\n", GPIO_V2_LINE_GET_VALUES_IOCTL );
    printf( "0x%08X GPIO_V2_LINE_SET_VALUES_IOCTL\n", GPIO_V2_LINE_SET_VALUES_IOCTL );


    return 0;
}