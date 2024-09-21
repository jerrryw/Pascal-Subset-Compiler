#ifndef ATTR_H
#define ATTR_H

typedef struct
{
    int   num;
    char* str;
} tokentype;

typedef struct
{
    int targetRegister;
} regInfo;

typedef struct
{
    int size;   // boolean = 4, int = 4.
    int count;  // if count > 0, it's an array.
} var_decl_type;

typedef struct
{
    char* str[1024];
    int   size;
} idlist;

typedef struct
{
    // char* str[1024];
    int   address;
    int   offset;  //in bytes
    int   targetRegister;
} lvalue_type;

typedef struct
{
    int label_if;
    int label_else;
    int label_endif;
} if_struct;

typedef struct
{
    int label_init;
    int label_loop;
    int label_endloop;
} loop_struct;


#endif