#include <stdint.h>
#include "neorv32.h"  // UART NEORV32

int main() 
{

  volatile uint32_t *mem = (uint32_t*)0x80000000; // adresse DMEM
  
  // Remplir la RAM avec des valeurs connues
  for (int i = 0; i < 256; i++) {
    mem[i] = 0xDEADBEEF;
  }
  
  neorv32_uart0_printf("RAM initialized\n");

  // Boucle de vérification
  while(1) 
  {
    for (int i = 0; i < 256; i++) 
    {
      if (mem[i] != 0xDEADBEEF) 
      {
        neorv32_uart0_printf("SEU detected at addr %d : got 0x%X\n", 
                              i, mem[i]);
      }
    }
  }
}