#ifndef SYMTAB_H
#define SYMTAB_H
#include <string.h>
#include <assert.h>

#define SYMTAB_MAX_SIZE  1024
#define SYMBOL_NOT_FOUND (-1)

/////////////////////////////////////////////////////////////////

extern char* CommentBuffer;

/////////////////////////////////////////////////////////////////

typedef int reg_id_t;   // register id
typedef int va_t;       // virtual address

typedef struct s_sym_entry
{
    char     name[1024];
    int      value;
    enum sym_type
    {
            SYM_TYPE_INVALID      = 0,
            SYM_TYPE_REGISTER     = 1,
            SYM_TYPE_VIRTUAL_ADDR = 2,
    } type;
} sym_entry_t;

/////////////////////////////////////////////////////////////////

va_t base_addr = STATIC_AREA_ADDRESS;     // 1024
int label_counter = 0;

/////////////////////////////////////////////////////////////////

int symtab_size = 0;
sym_entry_t symtab[SYMTAB_MAX_SIZE] = { 0 };

/////////////////////////////////////////////////////////////////

int get_label_and_inc()
{
    return label_counter++;
}

// Return the register ID for the given variable name.
reg_id_t find_symbol_reg(char* name)
{
    for (int i = 0; i < symtab_size; i++)
    {
        if (strcmp(name, symtab[i].name) == 0)
        {
            return symtab[i].value;
        }
    }
    return SYMBOL_NOT_FOUND;
}


// Add a variable <-> regId pair in the symbol table.
void add_symbol_common(char* name, int value, enum sym_type type)
{
    sprintf(CommentBuffer, "add_symbol_common(name:%s, value:%d, type:%d)", name, value, type);
    emitComment(CommentBuffer);
    int symbol_value = find_symbol_reg(name);

    if (SYMBOL_NOT_FOUND == symbol_value)
    {
        assert(symtab_size + 1 <= SYMTAB_MAX_SIZE);
        strcpy(symtab[symtab_size].name, name);
        symtab[symtab_size].value = value;      // regId and va use the same union struct.
        symtab[symtab_size].type  = type;
        symtab_size++;
    }
    else
    {
        sprintf(CommentBuffer, "Symbol exists in the table, value: %d", symbol_value);
        emitComment(CommentBuffer);
    }
}

void add_symbol_reg(char* name, int regId)
{
    add_symbol_common(name, regId, SYM_TYPE_REGISTER);
}

int my_aligned_up(int value, int alignment)
{
    int exceeds = value % alignment;
    int aligned_value = (exceeds == 0) ? value : value + (alignment - exceeds);

    assert((aligned_value % alignment) == 0);
    return aligned_value;
}

va_t add_symbol_array(char* name, int count, int unit_size)
{
    va_t aligned_addr = 0;
    int symbol_value = find_symbol_reg(name);

    if (SYMBOL_NOT_FOUND == symbol_value)
    {
        aligned_addr = my_aligned_up(base_addr, sizeof(int));
        base_addr = aligned_addr + count * unit_size;

        add_symbol_common(name, aligned_addr, SYM_TYPE_VIRTUAL_ADDR);
    }
    else
    {
        aligned_addr = symbol_value;
    }

    return aligned_addr;
}

#endif