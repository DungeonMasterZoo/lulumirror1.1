/*
 * Provenance: Gouda-percha's RAM-only boot guide, shim.c section:
 * https://failedattempts.neocities.org/part3a
 *
 * This shim constructs the ATF handoff parameters and jumps to BL31 after
 * the guide's USB-loaded boot components are placed at their expected RAM
 * addresses. UART writes below are diagnostic output, not a USB console.
 * Addresses and hardware assumptions are from the author's example and have
 * not been verified for this unit. This is experimental; do not deploy it.
 * The repository's get-shim-source.py verifies the unmodified upstream block
 * and prepends this explanatory header when reproducing this file.
 */
#include "atf_common.h"

//SHIM between SPL and loading a FIT image without verification
static inline void raw_write_daif(unsigned int daif);
void dcache_disable(void);
static inline unsigned long read_mpidr(void);
void uart_tx(char *str);
void *memset(void *inptr, int ch, size_t size);
static void bl31_entry(uintptr_t bl31_entry, uintptr_t bl32_entry,
               uintptr_t bl33_entry, uintptr_t fdt_addr);
void _start(void);


#define PRINT_MEM
#undef PRINT_MEM

void _start(void)
{
    uart_tx("Entering SHIM\n\r");
    uart_tx("Attempting to jump to ATF...\n\n\r");

    uintptr_t bl31_entry_addr = (uintptr_t ) 0x00920000;//0x00920000;   //ATF
    uintptr_t bl32_entry_addr = (uintptr_t ) 0xbe000000;    //TEE
    uintptr_t bl33_entry_addr = (uintptr_t ) 0x40200000;    //Uboot
    uintptr_t fdt_addr =        (uintptr_t ) 0x43000000;    //FDT
    
    bl31_entry(bl31_entry_addr, bl32_entry_addr, bl33_entry_addr, fdt_addr);

    uart_tx("Should never see this in SHIM\n\r");
}

void uart_tx(char *str)
{
    char * uart1_ptr = (char*)0x30890040;
    while(*str!='\0') //NOT checking bounds but who cares
    {
        *uart1_ptr=*str++;
        for(int i=0;i<100;i++)
        {
            for(int j=0;j<100;j++)
            {
                int k=i+j;
            }
        }
    }
}

//This is all ATF code copied to make bl31_entry work
static struct bl2_to_bl31_params_mem bl31_params_mem;
static struct bl31_params *bl2_to_bl31_params;

struct bl31_params *bl2_plat_get_bl31_params(uintptr_t bl32_entry,
                            uintptr_t bl33_entry,
                            uintptr_t fdt_addr)
{
    struct entry_point_info *bl32_ep_info;
    struct entry_point_info *bl33_ep_info;

    /*
     * Initialise the memory for all the arguments that needs to
     * be passed to BL31
     */
    memset(&bl31_params_mem, 0, sizeof(struct bl2_to_bl31_params_mem));

    /* Assign memory for TF related information */
    bl2_to_bl31_params = &bl31_params_mem.bl31_params;
    SET_PARAM_HEAD(bl2_to_bl31_params, ATF_PARAM_BL31, ATF_VERSION_1, 0);

    /* Fill BL31 related information */
    bl2_to_bl31_params->bl31_image_info = &bl31_params_mem.bl31_image_info;
    SET_PARAM_HEAD(bl2_to_bl31_params->bl31_image_info,
               ATF_PARAM_IMAGE_BINARY, ATF_VERSION_1, 0);

    /* Fill BL32 related information */
    bl2_to_bl31_params->bl32_ep_info = &bl31_params_mem.bl32_ep_info;
    bl32_ep_info = &bl31_params_mem.bl32_ep_info;
    SET_PARAM_HEAD(bl32_ep_info, ATF_PARAM_EP, ATF_VERSION_1,
               ATF_EP_SECURE);

    /* secure payload is optional, so set pc to 0 if absent */
    bl32_ep_info->args.arg3 = fdt_addr;
    bl32_ep_info->pc = bl32_entry ? bl32_entry : 0;
    bl32_ep_info->spsr = SPSR_64(MODE_EL1, MODE_SP_ELX,
                     DISABLE_ALL_EXECPTIONS);

    bl2_to_bl31_params->bl32_image_info = &bl31_params_mem.bl32_image_info;
    SET_PARAM_HEAD(bl2_to_bl31_params->bl32_image_info,
               ATF_PARAM_IMAGE_BINARY, ATF_VERSION_1, 0);

    /* Fill BL33 related information */
    bl2_to_bl31_params->bl33_ep_info = &bl31_params_mem.bl33_ep_info;
    bl33_ep_info = &bl31_params_mem.bl33_ep_info;
    SET_PARAM_HEAD(bl33_ep_info, ATF_PARAM_EP, ATF_VERSION_1,
               ATF_EP_NON_SECURE);

    /* BL33 expects to receive the primary CPU MPID (through x0) */
    bl33_ep_info->args.arg0 = 0xffff & read_mpidr();
    bl33_ep_info->pc = bl33_entry;
    bl33_ep_info->spsr = SPSR_64(MODE_EL2, MODE_SP_ELX,
                     DISABLE_ALL_EXECPTIONS);

    bl2_to_bl31_params->bl33_image_info = &bl31_params_mem.bl33_image_info;
    SET_PARAM_HEAD(bl2_to_bl31_params->bl33_image_info,
               ATF_PARAM_IMAGE_BINARY, ATF_VERSION_1, 0);

    return bl2_to_bl31_params;
}

typedef void (*atf_entry_t)(struct bl31_params *params, void *plat_params);

static void bl31_entry(uintptr_t bl31_entry, uintptr_t bl32_entry,
               uintptr_t bl33_entry, uintptr_t fdt_addr)
{
    struct bl31_params *bl31_params;
    atf_entry_t  atf_entry = (atf_entry_t)bl31_entry;

    bl31_params = bl2_plat_get_bl31_params(bl32_entry, bl33_entry, fdt_addr);

    raw_write_daif(SPSR_EXCEPTION_MASK);
    //TODO: See if we can survive without this dcache_disable();

    atf_entry((void *)bl31_params, (void *)fdt_addr);
}
void *memset(void *inptr, int ch, size_t size)
{
    char *ptr = inptr;
    char *end = ptr + size;

    while (ptr < end)
        *ptr++ = ch;

    return ptr;
}
static inline unsigned long read_mpidr(void)
{
    unsigned long val;
    asm volatile("mrs %0, mpidr_el1" : "=r" (val));
    return val;
}
static inline void raw_write_daif(unsigned int daif)
{
    __asm__ __volatile__("msr DAIF, %0\n\t" : : "r" (daif) : "memory");
}