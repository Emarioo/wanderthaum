package magic

import "core:fmt"
import "core:os"
import "core:strings"

TokenKind :: enum {
    T_EOF,

    // Literals
    T_IDENTIFIER,
    T_NUMBER,

    // Keywords
    T_INCIPERE,
    T_PERMANERE,
    T_PERFICERE,
    T_FINIS,
    T_SI,
    T_PRO,
    T_IN,
}

TokenFlags :: enum {
    F_NONE,
    F_SPACE,
    F_NEWLINE,
}


token_to_string :: proc (tok: ^Token) -> string {
    return tok.lexeme
}

Token :: struct {
    kind: TokenKind,
    lexeme: string,
    line: int,
    column: int,
    flags: TokenFlags,
}

EOF_TOKEN: Token = { .T_EOF, "", 0, 0, .F_NONE }

lex_text :: proc(text: string) -> [dynamic]Token {
    tokens: [dynamic]Token

    line : int = 1
    column: int = 1
    head : int
    for head < len(text) {
        cur_line := line
        cur_column := column
        c := text[head]
        c1 :u8  = 0
        if head+1 < len(text) {
            c1 = text[head+1]
        }
        head+=1
        column+=1

        if c == '#' {
            if len(tokens) > 0 {
                tokens[len(tokens)-1].flags |= .F_SPACE
            }
            for head < len(text) {
                if text[head] == '\n' {
                    if len(tokens) > 0 {
                        tokens[len(tokens)-1].flags |= .F_NEWLINE
                    }
                    head+=1
                    break
                }
                head+=1
            }
            line+=1
            column=1
            continue
        }
        if c == '\n' {
            line+=1
            column=1
            if len(tokens) > 0 {
                tokens[len(tokens)-1].flags |= .F_NEWLINE
            }
            continue
        }
        if c == ' ' || c == '\r' || c == '\t' || c == '\f' {
            if len(tokens) > 0 {
                tokens[len(tokens)-1].flags |= .F_SPACE
            }
            continue
        }

        if (c|32) >= 'a' && (c|32) <= 'z' {
            start := head - 1
            for head < len(text) {
                if text[head] == '_' || ((text[head]|32) >= 'a' && (text[head]|32) <= 'z') || ((text[head]) >= '0' && (text[head]) <= '9') {
                    head+=1
                    column+=1
                    continue
                }
                break
            }
            word : string = text[start:head]

            kind : TokenKind = .T_IDENTIFIER
            switch word {
                case "insipere": kind = .T_INCIPERE
                case "permanere": kind = .T_PERMANERE
                case "perficere": kind = .T_PERFICERE
                case "si": kind = .T_SI
                case "pro": kind = .T_PRO
                case "in": kind = .T_IN
                case "finis": kind = .T_FINIS
            }
            append(&tokens, Token{kind, word, cur_line, cur_column, .F_NONE})
            continue
        }

        if c >= '0' && c <= '9' {
            start := head - 1
            has_dot := false
            for head < len(text) {
                c := text[head]
                head+=1
                if c == '.' {
                    if has_dot {
                        fmt.println("Bad stuff")
                        os.exit(1)
                    }
                    has_dot=true
                    continue
                }
                if c >= '0' && c <= '9' {
                    continue
                }
                break
            }
            num : string = text[start:head]
            append(&tokens, Token{.T_NUMBER, num, cur_line, cur_column, .F_NONE})
            continue
        }
        append(&tokens, Token{cast(TokenKind) c, text[head-1:head], cur_line, cur_column, .F_NONE})
    }

    return tokens
}
