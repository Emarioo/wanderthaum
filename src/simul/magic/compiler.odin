package magic

import "core:os"
import "core:os/os2"
import "core:fmt"
import "core:strings"
import "core:c/libc"

/*
    Compiles spells
*/

Spell :: struct {
    text: string,

}

TranspileContext :: struct {
    head: int,
    tokens: [dynamic]Token,

    output: [dynamic]u8,

    error_jmpbuf: libc.jmp_buf,
    error_location: ^Token,
    error_message: string,
}

transpile_spell :: proc (text: string) {

    ctx: TranspileContext
    ctx.head = 0
    ctx.tokens = lex_text(text)

    if libc.setjmp(&ctx.error_jmpbuf) == 0 {
        parse_text(&ctx)
    } else {
        fmt.printfln("error {0}:{1}: {2}", ctx.error_location.line, ctx.error_location.column, ctx.error_message)
    }

    os2.mkdir("spells", 0o777)
    

    write_file("spells/spell.odin", string(ctx.output[:]))

    // @TODO .dll on windows
    compile_odin("spells", "libspell.so")
}

parse_error :: proc (ctx: ^TranspileContext, loc: ^Token, format: string, args: ..any) {
    ctx.error_message = fmt.aprintf(format, .. args)
    ctx.error_location = loc
    libc.longjmp(&ctx.error_jmpbuf, 1)
}

peek :: proc (ctx: ^TranspileContext, n: int = 0) -> ^Token {
    if ctx.head + n >= len(ctx.tokens) {
        return &EOF_TOKEN
    }
    return &ctx.tokens[ctx.head+n]
}
advance :: proc (ctx: ^TranspileContext, n: int = 1) {
    if ctx.head + n > len(ctx.tokens) {
        return
    }
    ctx.head += n
}

parse_text :: proc (ctx: ^TranspileContext) {

    append(&ctx.output, `
// AUTO GENERATED, DO NOT MODIFY, IT WILL BE OVERWRITTEN
package spell;

import "core:math/linalg/glsl"

vec3 :: glsl.vec3

Entity :: struct {
    pos: vec3,
    vel: vec3,
    rot: vec3,
    acc: vec3,
}
Catalyst :: struct {
    energy: f32,
    capacity: f32,
    generation: f32,
}

SpellContext :: struct {
    caster: ^Entity,
    catalyst: ^Catalyst,
    closest_entity : proc (origin: vec3, min_distance: f32, max_distance: f32) -> ^Entity,
    entities_in_sphere : proc (origin: vec3, min_distance: f32, max_distance: f32) -> []^Entity,
}

`)

    for {
        tok := peek(ctx)

        if tok.kind == .T_EOF {
            parse_error(ctx, tok, "Catalyst rejects the incomplete scripture.")
        }

        if tok.kind == .T_INCIPERE || tok.kind == .T_PERMANERE || tok.kind == .T_PERFICERE {
            advance(ctx)

            begin_text: string
            #partial switch tok.kind {
                case .T_INCIPERE: begin_text = 
                    "@(export) on_begin :: proc(ctx: ^SpellContext) {\n"
                case .T_PERMANERE: begin_text = 
                    "@(export) on_casting :: proc(ctx: ^SpellContext) {\n"
                case .T_PERFICERE: begin_text = 
                    "@(export) on_complete :: proc(ctx: ^SpellContext) {\n"
            }
            append(&ctx.output, begin_text)

            append(&ctx.output, `    incantator := ctx.caster
    catalyst := ctx.catalyst
    pulsus :: 1.0/60.0
    closest_entity := ctx.closest_entity
    entities_in_sphere := ctx.entities_in_sphere

    `)
            
            parse_block(ctx)

            append(&ctx.output, "}\n")

            tok = peek(ctx)
            if tok.kind == .T_FINIS {
                advance(ctx)
                break
            }
        } else {
            parse_error(ctx, tok, "Catalyst rejects the symbol %.", token_to_string(tok))
        }
    }
}

parse_block :: proc (ctx: ^TranspileContext) {
    for {
        tok := peek(ctx)

        if tok.kind == .T_EOF {
            parse_error(ctx, tok, "Catalyst rejects the incomplete scripture.")
        }

        if tok.kind == .T_FINIS {
            break
        } else {
            advance(ctx)
            append(&ctx.output, tok.lexeme)
            if (tok.flags & .F_NEWLINE) != .F_NONE {
                append(&ctx.output, "\n    ")
            } else if .F_NONE != (tok.flags & .F_SPACE) {
                append(&ctx.output, " ")
            }
        }
    }
}

compile_odin :: proc(src_path: string, dst_path: string) -> bool {

    out_arg: string = strings.concatenate([]string{"-out:",dst_path})
    args := []string{
        "odin",
        "build",
        src_path,
        // "-collection:lib=lib",
        "-debug",
        "-o:none",
        "-build-mode:shared",
        out_arg,
    }
      

    proce, err := os2.process_start(
        os2.Process_Desc{
            working_dir = "",
            command = args,
            env =  []string{},
            stderr = os2.stderr,
            stdout = os2.stdout,
            stdin = os2.stdin,
        }
    )

    if err != os2.ERROR_NONE {
        fmt.println("Failed to start Odin compiler:", err)
        os2.exit(1)
    }

    result, err2 := os2.process_wait(proce)

    if result.exit_code != 0 {
        fmt.println("Odin compilation failed")
        os2.exit(1)
    }

    fmt.println("Spell compiled successfully")
    return true
}

write_file :: proc(path: string, text: string) -> bool {

    dst, ok := os.open(path, os.O_CREATE | os.O_TRUNC | os.O_WRONLY, 0o777)
    if ok != os.General_Error.None {
        fmt.println("Failed to create destination file")
        return false
    }
    defer os.close(dst)

    bytes_written, write_ok := os.write(dst, transmute([]u8) text)
    if write_ok != os.General_Error.None {
        fmt.println("Write failed")
        return false
    }

    return true
}
