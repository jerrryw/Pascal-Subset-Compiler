%{
    #include <stdio.h>
    #include "attr.h"
    #include "instrutil.h"
    int yylex();
    void yyerror(char * s);
    #include "symtab.h"

    FILE *outfile;
    char *CommentBuffer;

    // output register is r0
    #define OUTPUT_REGISTER 0

    typedef int bool;
%}

%union
{
    tokentype     token;
    regInfo       targetReg;
    var_decl_type varType;
    idlist        idList;
    lvalue_type   lvalueType;
    if_struct     ifHeadType;
    loop_struct   loopHeadType;
}

%token PROG PERIOD VAR
%token ARRAY RANGE OF WRITELN THEN IF
%token BEG END ASG DO FOR
%token EQ NEQ LT LEQ
%token AND OR XOR NOT TRUE FALSE
%token ELSE
%token WHILE
%token <token> INT BOOL ID ICONST

%type <targetReg> exp rvalue condexp
%type <token> stype constant integer_constant boolean_constant
%type <varType> type
%type <idList> idlist
%type <lvalueType> lvalue
%type <ifHeadType> ifhead
%type <loopHeadType> whilehead forhead

%start program

%nonassoc EQ NEQ LT LEQ
%left '+' '-'
%left '*'

%nonassoc THEN
%nonassoc ELSE /* ELSE has a higher precedence than THEN */

%%
program
    :
        {
            emitComment("Assign STATIC_AREA_ADDRESS to register \"r0\"");
            emit(NOLABEL, LOADI, STATIC_AREA_ADDRESS, OUTPUT_REGISTER, EMPTY);
        }
        PROG ID ';' block PERIOD
        {

        }
    ;

block
    : variables cmpdstmt
        {

        }
    ;

variables: /* empty */
    | VAR vardcls
        {

        }
    ;

vardcls
    : vardcls vardcl ';'
        {

        }
    | vardcl ';'
        {

        }
    | error ';'
        {
            yyerror("***Error: illegal variable declaration\n");
        }
    ;

vardcl
    : idlist ':' type
        {
            emitComment("vardcl = idlist : type");

            for (int i = 0; i < $1.size; i++)
            {
                sprintf(CommentBuffer, "ID#%d: %s", i, $1.str[i]);
                emitComment(CommentBuffer);
            }

            sprintf(CommentBuffer, "type: size: %d, count: %d", $3.size, $3.count);
            emitComment(CommentBuffer);

            int newReg = find_symbol_reg($1.str);
            assert(newReg == SYMBOL_NOT_FOUND);

            if ($3.count == 0)
            {
                // not array
                for (int i = 0; i < $1.size; i++)
                {
                    newReg = NextRegister();
                    add_symbol_reg($1.str[i], newReg);
                }
            }
            else
            {
                // array
                for (int i = 0; i < $1.size; i++)
                {
                    add_symbol_array($1.str[i], $3.count, $3.size);
                }
            }
        }
    ;

idlist
    : idlist ',' ID
        {
            for (int i = 0; i < $1.size; i++)
            {
                $$.str[i] = $1.str[i];
            }
            $$.str[$$.size] = $3.str;
            $$.size = $1.size + 1;

            sprintf(CommentBuffer, "idlist = idlist , ID %s", $3.str);
            emitComment(CommentBuffer);

            for (int i = 0; i < $$.size; i++)
            {
                sprintf(CommentBuffer, "ID#%d: %s", i, $$.str[i]);
                emitComment(CommentBuffer);
            }
        }
    | ID
        {
            $$.str[0] = $1.str;
            $$.size   = 1;
            sprintf(CommentBuffer, "idlist = ID %s", $1.str);
            emitComment(CommentBuffer);
        }
    ;

type
    : ARRAY '[' integer_constant RANGE integer_constant ']' OF stype
        {
            // sprintf(CommentBuffer, "type = array [ ICONST .. ICONST ] of %s", $8.str);
            sprintf(CommentBuffer, "type = array [ %d .. %d ] of %s %s",
                $3.num, $5.num, $8.str, $8.num == INT ? "INT" : $8.num == BOOL ? "BOOL" : "Unknown_type");
            emitComment(CommentBuffer);
            assert($8.num == INT || $8.num == BOOL);
            $$.size = $8.num == INT ? sizeof(int) : $8.num == BOOL ? sizeof(bool) : 0;
            $$.count = $5.num - $3.num + 1; // array
            sprintf(CommentBuffer, "size: %d, count: %d", $$.size, $$.count);
            emitComment(CommentBuffer);
        }
    | stype
        {
            sprintf(CommentBuffer, "type = %s", $1.str);
            emitComment(CommentBuffer);
            $$.size = $1.num == INT ? sizeof(int) : $1.num == BOOL ? sizeof(bool) : 0;
            $$.count = 0; // non-array
            sprintf(CommentBuffer, "size: %d, count: %d", $$.size, $$.count);
            emitComment(CommentBuffer);
        }
    ;

stype
    : INT
        {
            sprintf(CommentBuffer, "stype = %s", $1.str);
            emitComment(CommentBuffer);
            $$.str = $1.str;
        }
    | BOOL
        {
            sprintf(CommentBuffer, "stype = %s", $1.str);
            emitComment(CommentBuffer);
            $$.str = $1.str;
        }
    ;

stmtlist
    : stmtlist ';' stmt
        {
            emitComment("stmtlist = stmtlist ; stmt");
        }
    | stmt
        {

        }
    | error
        {
            yyerror("***Error: illegal statement \n");
        }
    ;

stmt
    : ifstmt
        {
            emitComment("stmt = ifstmt");
        }
    | wstmt
        {
            emitComment("stmt = wstmt");
        }
    | fstmt
        {
            emitComment("stmt = fstmt");
        }
    | astmt
        {
            emitComment("stmt = astmt");
        }
    | writestmt
        {
            emitComment("stmt = writestmt");
        }
    | cmpdstmt
        {
            emitComment("stmt = cmpdstmt");
        }
    | error
        {
            emitComment("stmt = error");
        }
    ;

wstmt
    : whilehead condexp
        {
            emit(NOLABEL, CBR, $2.targetRegister, $1.label_loop, $1.label_endloop);
            emitComment("Body of \"WHILE\" construct starts here");
            emit($1.label_loop, NOP, EMPTY, EMPTY, EMPTY);
        }
        DO stmt
        {
            emit(NOLABEL, BR, $1.label_init, EMPTY, EMPTY);
            emit($1.label_endloop, NOP, EMPTY, EMPTY, EMPTY);
        }
    ;

whilehead
    : WHILE
        {
            emitComment("Control code for \"WHILE DO\"");
            $$.label_init    = get_label_and_inc();
            $$.label_loop    = get_label_and_inc();
            $$.label_endloop = get_label_and_inc();
            sprintf(CommentBuffer, "$$.label_init = %d", $$.label_init);
            emitComment(CommentBuffer);
            sprintf(CommentBuffer, "$$.label_loop = %d", $$.label_loop);
            emitComment(CommentBuffer);
            sprintf(CommentBuffer, "$$.label_endloop = %d", $$.label_endloop);
            emitComment(CommentBuffer);
            emit($$.label_init, NOP, EMPTY, EMPTY, EMPTY);
        }
    ;

fstmt
    : forhead ID ASG ICONST ',' ICONST
        {
            emitComment("forstmt = FOR ID ASG ICONST ',' ICONST DO stmt");
            int resReg = NextRegister();
            int cmpReg = NextRegister();
            emit(NOLABEL, LOADI, $6.num, cmpReg, EMPTY);
            int idReg  = find_symbol_reg($2.str);
            emit(NOLABEL, LOADI, $4.num, idReg, EMPTY);
            emit($1.label_init, NOP, EMPTY, EMPTY, EMPTY);

            emit(NOLABEL, CMPLE, idReg, cmpReg, resReg);
            emit(NOLABEL, CBR, resReg, $1.label_loop, $1.label_endloop);
            emitComment("Body of \"FOR\" construct starts here");
            emit($1.label_loop, NOP, EMPTY, EMPTY, EMPTY);
        }
        DO stmt
        {
            int idReg     = find_symbol_reg($2.str);
            int increment = NextRegister();
            emit(NOLABEL, LOADI, 1, increment, EMPTY);
            emit(NOLABEL, ADD, idReg, increment, idReg);
            emit(NOLABEL, BR, $1.label_init, EMPTY, EMPTY);
            emit($1.label_endloop, NOP, EMPTY, EMPTY, EMPTY);
        }
    ;

forhead
    : FOR
        {
            emitComment("Control code for \"FOR\"");
            $$.label_init    = get_label_and_inc();
            $$.label_loop    = get_label_and_inc();
            $$.label_endloop = get_label_and_inc();
        }
    ;

ifstmt
    : ifhead THEN stmt ELSE
        {
            emitComment("ifstmt = ifhead THEN stmt ELSE stmt");
            emit(NOLABEL, BR, $1.label_endif, EMPTY, EMPTY);
            emitComment("End of the \"true\" branch.");
            emitComment("Below is the \"false\" branch.");
            emit($1.label_else, NOP, EMPTY, EMPTY, EMPTY);
        }
        stmt
        {
            emit($1.label_endif, NOP, EMPTY, EMPTY, EMPTY);
        }
    | ifhead THEN stmt
        {
            emitComment("ifstmt = ifhead THEN stmt");
            emitComment("This is the \"false\" branch.");
            emit($1.label_else, NOP, EMPTY, EMPTY, EMPTY);
        }
    | error
        {
            emitComment("ifstmt = error");
        }
    ;

ifhead
    : IF condexp
        {
            $$.label_if    = get_label_and_inc();
            $$.label_else  = get_label_and_inc();
            $$.label_endif = get_label_and_inc();
            emit(NOLABEL, CBR, $2.targetRegister, $$.label_if, $$.label_else);
            emit($$.label_if, NOP, EMPTY, EMPTY, EMPTY);
        }
    ;

cmpdstmt
    : BEG stmtlist END
        {

        }
    ;

writestmt
    : WRITELN '(' exp ')'
        {
            emitComment("writestmt = WRITELN ( exp )");
            emit(NOLABEL, STORE, $3.targetRegister, OUTPUT_REGISTER, EMPTY);
            emit(NOLABEL, OUTPUT, STATIC_AREA_ADDRESS, EMPTY, EMPTY);
        }
    ;

astmt
    : lvalue ASG exp
        {
            emitComment("astmt = lvalue ASG exp");
            if ($1.targetRegister >= 0)
            {
                emitComment("asmt == targetRegister");
                emit(NOLABEL, I2I, $3.targetRegister, $1.targetRegister, EMPTY);
            }
            else
            {
                emitComment("asmt == array");
                emit(NOLABEL, STOREAI, $3.targetRegister, $1.offset, $1.address);
            }
        }
    ;

exp
    : rvalue
        {
            emitComment("exp = rvalue");

        }
    | exp '+' exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emit(NOLABEL, ADD, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp '-' exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emit(NOLABEL, SUB, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp '*' exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emit(NOLABEL, MULT, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp AND exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp and exp");
            emit(NOLABEL, L_AND, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp OR exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp or exp");
            emit(NOLABEL, L_OR, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp XOR exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp xor exp");
            emit(NOLABEL, L_XOR, $1.targetRegister, $3.targetRegister, newReg);
        }
    | NOT exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp not exp");
            emit(NOLABEL, NOP, $2.targetRegister, newReg, EMPTY);
        }
    | '(' exp ')'
        {
            emitComment("=(exp)=");
            $$.targetRegister = $2.targetRegister;
        }
    | constant
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp = constant");
            emit(NOLABEL, LOADI, $1.num, newReg, EMPTY);
        }
    | error
        {
            yyerror("***Error: illegal expression\n");
        }
    ;

condexp
    : exp NEQ exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp NEQ exp");
            emit(NOLABEL, CMPNE, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp EQ exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp EQ exp");
            emit(NOLABEL, CMPEQ, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp LT exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp LT exp");
            emit(NOLABEL, CMPLT, $1.targetRegister, $3.targetRegister, newReg);
        }
    | exp LEQ exp
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emitComment("exp LEQ exp");
            emit(NOLABEL, CMPLE, $1.targetRegister, $3.targetRegister, newReg);
        }
    | ID
        {
            int newReg = NextRegister();
            $$.targetRegister = newReg;

            int zeroReg = NextRegister();
            emit(NOLABEL, LOADI, 0, zeroReg, EMPTY);

            int idReg = find_symbol_reg($1.str);
            assert(idReg != SYMBOL_NOT_FOUND);
            emitComment("ID");
            emit(NOLABEL, CMPNE, idReg, zeroReg, newReg);
        }
    | boolean_constant
        {
            emitComment("boolean_constant");
            sprintf(CommentBuffer, "boolean_constant = %d", $1.num);
            emitComment(CommentBuffer);
            int newReg = NextRegister();
            $$.targetRegister = newReg;
            emit(NOLABEL, LOADI, $1.num, newReg, EMPTY);
        }
    | exp
        {
            emitComment("condexp = exp");
            $$.targetRegister = $1.targetRegister;
        }
    | error
        {
            yyerror("***Error: illegal conditional expression\n");
        }
    ;

lvalue
    : ID
        {
            int newReg = find_symbol_reg($1.str);
            if (newReg == SYMBOL_NOT_FOUND)
            {
                newReg = NextRegister();
                add_symbol_reg($1.str, newReg);
            }
            $$.targetRegister = newReg;
            emitComment("lvalue = ID");
            sprintf(CommentBuffer, "ID: $1.str == \"%s\", $1.targetRegister == \"%d\"", $1.str, $$.targetRegister);
            emitComment(CommentBuffer);
        }
    | ID '[' exp ']'
        {
            int newReg = NextRegister();
            emit(NOLABEL, LOADI, 4, newReg, EMPTY);

            int tempReg = NextRegister();
            emit(NOLABEL, MULT, newReg, $3.targetRegister, tempReg);

            $$.address = find_symbol_reg($1.str);
            $$.offset  = tempReg;
            $$.targetRegister = -1;

            emitComment("lvalue = ID [exp]");
            sprintf(CommentBuffer, "$1.str == \"%s\", $$.address == \"%d\", $$.offset == \"r%d\"", $1.str, $$.address, $$.offset);
            emitComment(CommentBuffer);
        }
    ;

rvalue
    : ID
        {
            int newReg = find_symbol_reg($1.str);
            if (newReg == SYMBOL_NOT_FOUND)
            {
                newReg = NextRegister();
                add_symbol_reg($1.str, newReg);
            }
            $$.targetRegister = newReg;
            emitComment("rvalue = ID");
            sprintf(CommentBuffer, "ID: $1.str == \"%s\", $1.targetRegister == \"%d\"", $1.str, $$.targetRegister);
            emitComment(CommentBuffer);
        }
    | ID '[' exp ']'
        {
            emitComment("rvalue = ID [ exp ] ");
            int address = find_symbol_reg($1.str);
            int newReg = NextRegister();
            emit(NOLABEL, LOADI, 4, newReg, EMPTY);

            int tempReg = NextRegister();
            emit(NOLABEL, MULT, newReg, $3.targetRegister, tempReg);

            $$.targetRegister = NextRegister();
            emit(NOLABEL, LOADAI, tempReg, address, $$.targetRegister);

            emitComment("rvalue = ID [exp]");
            sprintf(CommentBuffer, "$1.str == \"%s\", address == \"%d\", tempReg == \"r%d\"", $1.str, address, tempReg);
            emitComment(CommentBuffer);
        }
    ;

constant
    : integer_constant
    | boolean_constant
    ;

integer_constant
    : ICONST
        {
            sprintf(CommentBuffer, "integer_constant = %d", $1.num);
            emitComment(CommentBuffer);
            $$.num = $1.num;
        }
    ;

boolean_constant
    : TRUE
        {
            emitComment("boolean_constant = TRUE");
            $$.num = 1;
        }
    | FALSE
        {
            emitComment("boolean_constant = FALSE");
            $$.num = 0;
        }
    ;

%%

void yyerror(char* s)
{
    fprintf(stderr,"%s\n",s);
    fflush(stderr);
}

int main()
{
    printf("\n          Code Generator\n\n");
    outfile = fopen("iloc.out", "w");

    if (outfile == NULL) {
        printf("ERROR: cannot open output file \"iloc.out\".\n");
        return -1;
    }

    CommentBuffer = (char *) malloc(500);
    printf("1\t");
    yyparse();
    printf("\n");

    fclose(outfile);
    return 0;
}