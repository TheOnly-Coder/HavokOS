#!/usr/bin/env python3
"""
Havok Scripting Library (HSL) Interpreter v1.0
A domain-specific language for customizing HavokOS.
File extension: .hsl
"""
import sys, os, re, json, glob, subprocess, signal

# ============================================================
# Tokenizer
# ============================================================

class TokenType:
    IDENT = 'IDENT'
    STRING = 'STRING'
    NUMBER = 'NUMBER'
    BOOL = 'BOOL'
    LBRACE = 'LBRACE'
    RBRACE = 'RBRACE'
    LBRACKET = 'LBRACKET'
    RBRACKET = 'RBRACKET'
    LPAREN = 'LPAREN'
    RPAREN = 'RPAREN'
    COLON = 'COLON'
    COMMA = 'COMMA'
    DOT = 'DOT'
    ARROW = 'ARROW'
    ASSIGN = 'ASSIGN'
    HASH_COMMENT = 'HASH_COMMENT'
    ON = 'ON'
    EVENT = 'EVENT'
    IF = 'IF'
    ELSE = 'ELSE'
    WHILE = 'WHILE'
    FOR = 'FOR'
    IN = 'IN'
    FUNC = 'FUNC'
    RETURN = 'RETURN'
    IMPORT = 'IMPORT'
    PLUS = 'PLUS'
    MINUS = 'MINUS'
    STAR = 'STAR'
    SLASH = 'SLASH'
    EQ = 'EQ'
    NEQ = 'NEQ'
    LT = 'LT'
    GT = 'GT'
    LTE = 'LTE'
    GTE = 'GTE'
    AND = 'AND'
    OR = 'OR'
    NOT = 'NOT'
    EOF = 'EOF'

class Token:
    def __init__(self, type, value, line=0):
        self.type = type
        self.value = value
        self.line = line
    def __repr__(self):
        return f'Token({self.type}, {self.value!r})'

class Tokenizer:
    KEYWORDS = {
        'on': TokenType.ON, 'if': TokenType.IF, 'else': TokenType.ELSE,
        'while': TokenType.WHILE, 'for': TokenType.FOR, 'in': TokenType.IN,
        'func': TokenType.FUNC, 'return': TokenType.RETURN, 'import': TokenType.IMPORT,
        'true': TokenType.BOOL, 'false': TokenType.BOOL,
        'and': TokenType.AND, 'or': TokenType.OR, 'not': TokenType.NOT,
    }
    EVENTS = {
        'click', 'dblclick', 'hover', 'enter', 'leave', 'change',
        'key_press', 'key_release', 'focus', 'unfocus', 'close', 'open',
        'load', 'save', 'timer', 'startup', 'shutdown',
    }

    def __init__(self, source):
        self.source = source
        self.pos = 0
        self.line = 1
        self.tokens = []

    def peek(self):
        if self.pos < len(self.source):
            return self.source[self.pos]
        return '\0'

    def advance(self):
        ch = self.source[self.pos]
        self.pos += 1
        if ch == '\n':
            self.line += 1
        return ch

    def tokenize(self):
        while self.pos < len(self.source):
            ch = self.peek()

            # Skip whitespace
            if ch in ' \t\r\n':
                self.advance()
                continue

            # Comments
            if ch == '#':
                while self.pos < len(self.source) and self.peek() != '\n':
                    self.advance()
                continue

            # Strings
            if ch == '"':
                self.advance()
                s = ''
                while self.pos < len(self.source) and self.peek() != '"':
                    if self.peek() == '\\' and self.pos + 1 < len(self.source):
                        self.advance()
                        esc = self.advance()
                        s += {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"'}.get(esc, esc)
                    else:
                        s += self.advance()
                self.advance()  # closing quote
                self.tokens.append(Token(TokenType.STRING, s, self.line))
                continue

            # Numbers
            if ch.isdigit() or (ch == '-' and self.pos + 1 < len(self.source) and self.source[self.pos + 1].isdigit()):
                num = ''
                if ch == '-':
                    num += self.advance()
                while self.pos < len(self.source) and (self.peek().isdigit() or self.peek() == '.'):
                    num += self.advance()
                val = float(num) if '.' in num else int(num)
                self.tokens.append(Token(TokenType.NUMBER, val, self.line))
                continue

            # Identifiers and keywords
            if ch.isalpha() or ch == '_':
                ident = ''
                while self.pos < len(self.source) and (self.peek().isalnum() or self.peek() == '_'):
                    ident += self.advance()
                lower = ident.lower()
                if lower in self.KEYWORDS:
                    ttype = self.KEYWORDS[lower]
                    val = True if lower == 'true' else (False if lower == 'false' else lower)
                    self.tokens.append(Token(ttype, val, self.line))
                elif lower in self.EVENTS:
                    self.tokens.append(Token(TokenType.EVENT, lower, self.line))
                else:
                    self.tokens.append(Token(TokenType.IDENT, ident, self.line))
                continue

            # Two-char operators (must come before single-char)
            if ch == '=' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '=':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.EQ, '==', self.line))
                continue
            if ch == '!' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '=':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.NEQ, '!=', self.line))
                continue
            if ch == '<' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '=':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.LTE, '<=', self.line))
                continue
            if ch == '>' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '=':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.GTE, '>=', self.line))
                continue
            if ch == '&' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '&':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.AND, '&&', self.line))
                continue
            if ch == '|' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '|':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.OR, '||', self.line))
                continue

            # Symbols
            sym_map = {
                '{': TokenType.LBRACE, '}': TokenType.RBRACE,
                '[': TokenType.LBRACKET, ']': TokenType.RBRACKET,
                '(': TokenType.LPAREN, ')': TokenType.RPAREN,
                ':': TokenType.COLON, ',': TokenType.COMMA,
                '.': TokenType.DOT, '+': TokenType.PLUS, '-': TokenType.MINUS,
                '*': TokenType.STAR, '/': TokenType.SLASH,
                '<': TokenType.LT, '>': TokenType.GT, '!': TokenType.NOT,
            }
            if ch in sym_map:
                self.advance()
                self.tokens.append(Token(sym_map[ch], ch, self.line))
                continue

            if ch == '=' and self.pos + 1 < len(self.source) and self.source[self.pos + 1] == '>':
                self.advance(); self.advance()
                self.tokens.append(Token(TokenType.ARROW, '=>', self.line))
                continue

            if ch == '=' and (self.pos + 1 >= len(self.source) or self.source[self.pos + 1] != '='):
                self.advance()
                self.tokens.append(Token(TokenType.ASSIGN, '=', self.line))
                continue

            if ch == '-':
                self.advance()
                if self.pos < len(self.source) and self.peek() == '>':
                    self.advance()
                    self.tokens.append(Token(TokenType.ARROW, '->', self.line))
                else:
                    self.tokens.append(Token(TokenType.IDENT, '-', self.line))
                continue

            # Skip unknown
            self.advance()

        self.tokens.append(Token(TokenType.EOF, None, self.line))
        return self.tokens


# ============================================================
# AST Nodes
# ============================================================

class Node:
    pass

class Program(Node):
    def __init__(self, statements):
        self.statements = statements

class BlockDef(Node):
    def __init__(self, name, args, body, line=0):
        self.name = name
        self.args = args
        self.body = body
        self.line = line

class PropAssign(Node):
    def __init__(self, name, value, line=0):
        self.name = name
        self.value = value
        self.line = line

class EventDef(Node):
    def __init__(self, event_name, body, line=0):
        self.event_name = event_name
        self.body = body
        self.line = line

class FuncDef(Node):
    def __init__(self, name, params, body, line=0):
        self.name = name
        self.params = params
        self.body = body
        self.line = line

class FuncCall(Node):
    def __init__(self, name, args, line=0):
        self.name = name
        self.args = args
        self.line = line

class DotAccess(Node):
    def __init__(self, obj, attr, line=0):
        self.obj = obj
        self.attr = attr
        self.line = line

class DotAssign(Node):
    def __init__(self, obj, attr, value, line=0):
        self.obj = obj
        self.attr = attr
        self.value = value
        self.line = line

class IfStmt(Node):
    def __init__(self, condition, then_body, else_body=None, line=0):
        self.condition = condition
        self.then_body = then_body
        self.else_body = else_body
        self.line = line

class WhileLoop(Node):
    def __init__(self, condition, body, line=0):
        self.condition = condition
        self.body = body
        self.line = line

class ForLoop(Node):
    def __init__(self, var, iterable, body, line=0):
        self.var = var
        self.iterable = iterable
        self.body = body
        self.line = line

class ReturnStmt(Node):
    def __init__(self, value, line=0):
        self.value = value
        self.line = line

class ImportStmt(Node):
    def __init__(self, module, line=0):
        self.module = module
        self.line = line

class StringLit:
    def __init__(self, value): self.value = value
class NumLit:
    def __init__(self, value): self.value = value
class BoolLit:
    def __init__(self, value): self.value = value

class VarRef:
    def __init__(self, name, line=0):
        self.name = name
        self.line = line

class BinOp:
    def __init__(self, op, left, right, line=0):
        self.op = op
        self.left = left
        self.right = right
        self.line = line


# ============================================================
# Parser
# ============================================================

class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else Token(TokenType.EOF, None)

    def advance(self):
        t = self.tokens[self.pos]
        self.pos += 1
        return t

    def expect(self, ttype):
        t = self.advance()
        if t.type != ttype:
            raise SyntaxError(f"Expected {ttype} but got {t.type} ({t.value!r}) at line {t.line}")
        return t

    def parse(self):
        stmts = []
        while self.peek().type != TokenType.EOF:
            stmt = self.parse_statement()
            if stmt:
                stmts.append(stmt)
        return Program(stmts)

    def parse_statement(self):
        t = self.peek()

        if t.type == TokenType.IMPORT:
            return self.parse_import()
        if t.type == TokenType.FUNC:
            return self.parse_func()
        if t.type == TokenType.IF:
            return self.parse_if()
        if t.type == TokenType.WHILE:
            return self.parse_while()
        if t.type == TokenType.FOR:
            return self.parse_for()
        if t.type == TokenType.RETURN:
            return self.parse_return()
        if t.type == TokenType.IDENT:
            return self.parse_ident_statement()

        self.advance()  # skip unknown
        return None

    def parse_import(self):
        t = self.advance()
        module = self.expect(TokenType.IDENT).value
        return ImportStmt(module, t.line)

    def parse_func(self):
        t = self.advance()
        name = self.expect(TokenType.IDENT).value
        self.expect(TokenType.LPAREN)
        params = []
        if self.peek().type != TokenType.RPAREN:
            params.append(self.expect(TokenType.IDENT).value)
            while self.peek().type == TokenType.COMMA:
                self.advance()
                params.append(self.expect(TokenType.IDENT).value)
        self.expect(TokenType.RPAREN)
        body = self.parse_block()
        return FuncDef(name, params, body, t.line)

    def parse_if(self):
        t = self.advance()
        cond = self.parse_expr()
        then_body = self.parse_block()
        else_body = None
        if self.peek().type == TokenType.ELSE:
            self.advance()
            else_body = self.parse_block()
        return IfStmt(cond, then_body, else_body, t.line)

    def parse_while(self):
        t = self.advance()
        cond = self.parse_expr()
        body = self.parse_block()
        return WhileLoop(cond, body, t.line)

    def parse_for(self):
        t = self.advance()
        var = self.expect(TokenType.IDENT).value
        # Handle both 'for var: expr' and 'for var in expr'
        if self.peek().type == TokenType.IN:
            self.advance()  # consume 'in'
        else:
            self.expect(TokenType.COLON)
        iterable = self.parse_expr()
        body = self.parse_block()
        return ForLoop(var, iterable, body, t.line)

    def parse_return(self):
        t = self.advance()
        val = self.parse_expr()
        return ReturnStmt(val, t.line)

    def parse_ident_statement(self):
        name_tok = self.advance()
        name = name_tok.value
        next_t = self.peek()

        # name "label" { ... } -> BlockDef (UI element or app)
        if next_t.type == TokenType.STRING:
            label = self.advance().value
            args = {}
            if self.peek().type == TokenType.LPAREN:
                self.advance()
                if self.peek().type != TokenType.RPAREN:
                    k = self.expect(TokenType.IDENT).value
                    self.expect(TokenType.COLON)
                    v = self.parse_expr()
                    args[k] = v
                    while self.peek().type == TokenType.COMMA:
                        self.advance()
                        k = self.expect(TokenType.IDENT).value
                        self.expect(TokenType.COLON)
                        v = self.parse_expr()
                        args[k] = v
                self.expect(TokenType.RPAREN)
            body = self.parse_block()
            return BlockDef(name, {'_label': label, **args}, body, name_tok.line)

        # name(args) -> function call
        if next_t.type == TokenType.LPAREN:
            return self.parse_func_call_tail(name, name_tok.line)

        # name.prop = value
        if next_t.type == TokenType.DOT:
            self.advance()
            attr = self.expect(TokenType.IDENT).value
            if self.peek().type == TokenType.ASSIGN:
                self.advance()
                val = self.parse_expr()
                return DotAssign(name, attr, val, name_tok.line)
            else:
                return DotAccess(name, attr, name_tok.line)

        # name = value
        if next_t.type == TokenType.ASSIGN:
            self.advance()
            val = self.parse_expr()
            return PropAssign(name, val, name_tok.line)

        # name { ... } -> unnamed block
        if next_t.type == TokenType.LBRACE:
            body = self.parse_block()
            return BlockDef(name, {}, body, name_tok.line)

        return None

    def parse_func_call_tail(self, name, line):
        self.expect(TokenType.LPAREN)
        args = []
        if self.peek().type != TokenType.RPAREN:
            args.append(self.parse_expr())
            while self.peek().type == TokenType.COMMA:
                self.advance()
                args.append(self.parse_expr())
        self.expect(TokenType.RPAREN)
        return FuncCall(name, args, line)

    def parse_block(self):
        self.expect(TokenType.LBRACE)
        stmts = []
        while self.peek().type != TokenType.RBRACE and self.peek().type != TokenType.EOF:
            stmt = self.parse_statement()
            if stmt:
                stmts.append(stmt)
        self.expect(TokenType.RBRACE)
        return stmts

    def parse_expr(self):
        left = self._parse_primary()
        return self._parse_binary_ops(left, 0)

    def _parse_primary(self):
        t = self.peek()
        if t.type == TokenType.STRING:
            self.advance()
            return StringLit(t.value)
        if t.type == TokenType.NUMBER:
            self.advance()
            return NumLit(t.value)
        if t.type == TokenType.BOOL:
            self.advance()
            return BoolLit(t.value)
        if t.type == TokenType.LBRACKET:
            return self.parse_list()
        if t.type == TokenType.NOT:
            self.advance()
            operand = self._parse_primary()
            return FuncCall('__not__', [operand], t.line)
        if t.type == TokenType.MINUS:
            self.advance()
            operand = self._parse_primary()
            return FuncCall('__neg__', [operand], t.line)
        if t.type == TokenType.IDENT:
            name = self.advance().value
            if self.peek().type == TokenType.LPAREN:
                return self.parse_func_call_tail(name, t.line)
            if self.peek().type == TokenType.DOT:
                self.advance()
                attr = self.expect(TokenType.IDENT).value
                return DotAccess(name, attr, t.line)
            return VarRef(name, t.line)
        # fallback
        self.advance()
        return StringLit('')

    # Operator precedence (lowest to highest)
    PRECEDENCE = {
        '||': 1, '&&': 2,
        '==': 3, '!=': 3, '<': 4, '>': 4, '<=': 4, '>=': 4,
        '+': 5, '-': 5, '*': 6, '/': 6,
    }
    OP_TOKENS = {
        TokenType.OR: '||', TokenType.AND: '&&',
        TokenType.EQ: '==', TokenType.NEQ: '!=',
        TokenType.LT: '<', TokenType.GT: '>', TokenType.LTE: '<=', TokenType.GTE: '>=',
        TokenType.PLUS: '+', TokenType.MINUS: '-',
        TokenType.STAR: '*', TokenType.SLASH: '/',
    }

    def _parse_binary_ops(self, left, min_prec):
        while True:
            t = self.peek()
            op = self.OP_TOKENS.get(t.type)
            if op is None or self.PRECEDENCE.get(op, 0) < min_prec:
                break
            self.advance()
            right = self._parse_primary()
            # Right-associative for same precedence
            next_prec = self.PRECEDENCE.get(op, 0) + 1
            right = self._parse_binary_ops(right, next_prec)
            left = BinOp(op, left, right, t.line)
        return left

    def parse_list(self):
        self.expect(TokenType.LBRACKET)
        items = []
        if self.peek().type != TokenType.RBRACKET:
            items.append(self.parse_expr())
            while self.peek().type == TokenType.COMMA:
                self.advance()
                items.append(self.parse_expr())
        self.expect(TokenType.RBRACKET)
        return items


# ============================================================
# Runtime Environment
# ============================================================

class HSLReturn(Exception):
    def __init__(self, value):
        self.value = value

class HSLEnvironment:
    def __init__(self, parent=None):
        self.vars = {}
        self.parent = parent
        self.functions = {}
        self.widgets = {}
        self.widget_tree = []

    def get(self, name):
        if name in self.vars:
            return self.vars[name]
        if self.parent:
            return self.parent.get(name)
        return None

    def set(self, name, value):
        self.vars[name] = value

    def get_func(self, name):
        if name in self.functions:
            return self.functions[name]
        if self.parent:
            return self.parent.get_func(name)
        return None

    def set_func(self, name, func):
        self.functions[name] = func


class HSLInterpreter:
    def __init__(self, stdlib_path=None):
        self.global_env = HSLEnvironment()
        self.stdlib_path = stdlib_path or '/usr/share/havok/hsl'
        self._load_builtins()

    def _load_builtins(self):
        env = self.global_env

        def hsl_print(args):
            parts = []
            for a in args:
                if isinstance(a, str): parts.append(a)
                elif isinstance(a, (int, float)): parts.append(str(a))
                elif isinstance(a, bool): parts.append('true' if a else 'false')
                elif isinstance(a, list): parts.append(str(a))
                else: parts.append(str(a))
            print(' '.join(parts), file=sys.stderr)
            return None

        def hsl_shell(args):
            if not args: return ''
            cmd = args[0] if isinstance(args[0], str) else str(args[0])
            try:
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                return result.stdout.strip()
            except Exception as e:
                return f'Error: {e}'

        def hsl_read_file(args):
            if not args: return ''
            try:
                with open(args[0], 'r') as f:
                    return f.read()
            except Exception as e:
                return f'Error: {e}'

        def hsl_write_file(args):
            if len(args) < 2: return False
            try:
                with open(args[0], 'w') as f:
                    f.write(str(args[1]))
                return True
            except Exception as e:
                return False

        def hsl_list_dir(args):
            path = args[0] if args else '.'
            try:
                return sorted(os.listdir(path))
            except Exception as e:
                return [f'Error: {e}']

        def hsl_exists(args):
            if not args: return False
            return os.path.exists(args[0])

        def hsl_mkdir(args):
            if not args: return False
            try:
                os.makedirs(args[0], exist_ok=True)
                return True
            except:
                return False

        def hsl_len(args):
            if not args: return 0
            return len(args[0]) if isinstance(args[0], (str, list)) else 0

        def hsl_str(args):
            return str(args[0]) if args else ''

        def hsl_int(args):
            try:
                return int(args[0]) if args else 0
            except:
                return 0

        def hsl_float(args):
            try:
                return float(args[0]) if args else 0.0
            except:
                return 0.0

        def hsl_type(args):
            if not args: return 'null'
            v = args[0]
            if isinstance(v, str): return 'string'
            if isinstance(v, bool): return 'bool'
            if isinstance(v, int): return 'int'
            if isinstance(v, float): return 'float'
            if isinstance(v, list): return 'list'
            if isinstance(v, dict): return 'dict'
            return 'object'

        def hsl_range(args):
            start = int(args[0]) if len(args) > 0 else 0
            stop = int(args[1]) if len(args) > 1 else start
            step = int(args[2]) if len(args) > 2 else 1
            if len(args) == 1:
                return list(range(start))
            return list(range(start, stop, step))

        def hsl_append(args):
            if len(args) < 2 or not isinstance(args[0], list): return None
            args[0].append(args[1])
            return args[0]

        def hsl_join(args):
            if len(args) < 2: return ''
            sep = str(args[0])
            lst = args[1] if isinstance(args[1], list) else [str(args[1])]
            return sep.join(str(x) for x in lst)

        def hsl_split(args):
            if not args or not isinstance(args[0], str): return []
            sep = str(args[1]) if len(args) > 1 else ' '
            return args[0].split(sep)

        def hsl_upper(args):
            return str(args[0]).upper() if args else ''

        def hsl_lower(args):
            return str(args[0]).lower() if args else ''

        def hsl_replace(args):
            if len(args) < 3 or not isinstance(args[0], str): return ''
            return args[0].replace(str(args[1]), str(args[2]))

        def hsl_contains(args):
            if len(args) < 2: return False
            return str(args[1]) in str(args[0])

        def hsl_starts_with(args):
            if len(args) < 2: return False
            return str(args[0]).startswith(str(args[1]))

        def hsl_ends_with(args):
            if len(args) < 2: return False
            return str(args[0]).endswith(str(args[1]))

        def hsl_trim(args):
            return str(args[0]).strip() if args else ''

        def hsl_getenv(args):
            return os.environ.get(args[0] if args else '', '')

        def hsl_sleep(args):
            import time
            time.sleep(float(args[0]) if args else 1)
            return None

        def hsl_now(args):
            import time
            return time.time()

        def hsl_gtk_builder(args):
            """Generate GTK UI from HSL block definitions stored in the widget tree."""
            return self.global_env.widget_tree

        env.functions = {
            'print': hsl_print, 'shell': hsl_shell,
            'read_file': hsl_read_file, 'write_file': hsl_write_file,
            'list_dir': hsl_list_dir, 'exists': hsl_exists, 'mkdir': hsl_mkdir,
            'len': hsl_len, 'str': hsl_str, 'int': hsl_int, 'float': hsl_float,
            'type': hsl_type, 'range': hsl_range,
            'append': hsl_append, 'join': hsl_join, 'split': hsl_split,
            'upper': hsl_upper, 'lower': hsl_lower, 'replace': hsl_replace,
            'contains': hsl_contains, 'starts_with': hsl_starts_with,
            'ends_with': hsl_ends_with, 'trim': hsl_trim,
            'getenv': hsl_getenv, 'sleep': hsl_sleep, 'now': hsl_now,
            'gtk_builder': hsl_gtk_builder,
        }

    def eval_node(self, node, env=None):
        if env is None:
            env = self.global_env

        if isinstance(node, Program):
            result = None
            for stmt in node.statements:
                result = self.eval_node(stmt, env)
            return result

        if isinstance(node, BlockDef):
            block_info = {
                'type': node.name,
                'label': node.args.get('_label', ''),
                'args': {k: v for k, v in node.args.items() if k != '_label'},
                'children': [],
                'events': {},
            }
            for stmt in node.body:
                if isinstance(stmt, BlockDef):
                    child = self.eval_node(stmt, env)
                    if isinstance(child, dict) and 'type' in child:
                        block_info['children'].append(child)
                elif isinstance(stmt, PropAssign):
                    block_info['args'][stmt.name] = self.eval_expr(stmt.value, env)
                elif isinstance(stmt, EventDef):
                    block_info['events'][stmt.event_name] = stmt.body
                elif isinstance(stmt, FuncDef):
                    env.set_func(stmt.name, stmt)
            env.widget_tree.append(block_info)
            return block_info

        if isinstance(node, FuncDef):
            env.set_func(node.name, node)
            return None

        if isinstance(node, ImportStmt):
            return self._handle_import(node.module, env)

        if isinstance(node, PropAssign):
            val = self.eval_expr(node.value, env)
            env.set(node.name, val)
            return val

        if isinstance(node, DotAssign):
            obj = env.get(node.obj)
            if isinstance(obj, dict):
                obj[node.attr] = self.eval_expr(node.value, env)
            return None

        if isinstance(node, IfStmt):
            cond = self.eval_expr(node.condition, env)
            if cond:
                return self.eval_body(node.then_body, env)
            elif node.else_body:
                return self.eval_body(node.else_body, env)
            return None

        if isinstance(node, WhileLoop):
            while self.eval_expr(node.condition, env):
                self.eval_body(node.body, env)
            return None

        if isinstance(node, ForLoop):
            iterable = self.eval_expr(node.iterable, env)
            if isinstance(iterable, (list, range)):
                for item in list(iterable):
                    env.set(node.var, item)
                    self.eval_body(node.body, env)
            return None

        if isinstance(node, ReturnStmt):
            val = self.eval_expr(node.value, env)
            raise HSLReturn(val)

        if isinstance(node, FuncCall):
            return self._call_func(node, env)

        return None

    def eval_body(self, stmts, env):
        result = None
        for stmt in stmts:
            result = self.eval_node(stmt, env)
        return result

    def eval_expr(self, node, env=None):
        if env is None:
            env = self.global_env
        if isinstance(node, StringLit): return node.value
        if isinstance(node, NumLit): return node.value
        if isinstance(node, BoolLit): return node.value
        if isinstance(node, list): return [self.eval_expr(e, env) for e in node]
        if isinstance(node, VarRef): return env.get(node.name)
        if isinstance(node, BinOp): return self._eval_binop(node, env)
        if isinstance(node, DotAccess):
            obj = env.get(node.obj)
            if isinstance(obj, dict) and node.attr in obj:
                return obj[node.attr]
            return None
        if isinstance(node, FuncCall):
            return self._call_func(node, env)
        return None

    def _eval_binop(self, node, env):
        left = self.eval_expr(node.left, env)
        right = self.eval_expr(node.right, env)
        op = node.op
        if op == '+': return (left or '') + (right or '')
        if op == '-': return (left or 0) - (right or 0)
        if op == '*': return (left or 0) * (right or 0)
        if op == '/':
            r = right or 1
            return left / r if isinstance(left, float) or isinstance(r, float) else int(left) // int(r)
        if op == '==': return left == right
        if op == '!=': return left != right
        if op == '<': return left < right
        if op == '>': return left > right
        if op == '<=': return left <= right
        if op == '>=': return left >= right
        if op == '&&': return bool(left) and bool(right)
        if op == '||': return bool(left) or bool(right)
        return None

    def _call_func(self, node, env):
        args = [self.eval_expr(a, env) for a in node.args]
        func = env.get_func(node.name)
        if func is None:
            print(f"[HSL] Warning: unknown function '{node.name}' at line {node.line}", file=sys.stderr)
            return None
        if callable(func):
            try:
                return func(args)
            except Exception as e:
                print(f"[HSL] Error calling '{node.name}': {e}", file=sys.stderr)
                return None
        if isinstance(func, FuncDef):
            local_env = HSLEnvironment(parent=env)
            for i, param in enumerate(func.params):
                local_env.set(param, args[i] if i < len(args) else None)
            try:
                self.eval_body(func.body, local_env)
            except HSLReturn as r:
                return r.value
            return None
        return None

    def _handle_import(self, module, env):
        paths = []
        if os.path.isdir(self.stdlib_path):
            paths.append(os.path.join(self.stdlib_path, f'{module}.hsl'))
        paths.append(f'{module}.hsl')
        for p in paths:
            if os.path.isfile(p):
                return self.run_file(p, env)
        print(f"[HSL] Warning: module '{module}' not found", file=sys.stderr)
        return None

    def run_source(self, source, env=None):
        tokenizer = Tokenizer(source)
        tokens = tokenizer.tokenize()
        parser = Parser(tokens)
        ast = parser.parse()
        return self.eval_node(ast, env)

    def run_file(self, filepath, env=None):
        with open(filepath, 'r') as f:
            source = f.read()
        return self.run_source(source, env)

    def run_directory(self, dirpath):
        """Run all .hsl files in a directory, sorted by name."""
        results = []
        if not os.path.isdir(dirpath):
            return results
        for f in sorted(glob.glob(os.path.join(dirpath, '*.hsl'))):
            try:
                result = self.run_file(f)
                results.append((f, result))
            except Exception as e:
                print(f"[HSL] Error in {f}: {e}", file=sys.stderr)
        return results


# ============================================================
# REPL
# ============================================================

def repl():
    print("Havok Scripting Library (HSL) v1.0")
    print("Type expressions or statements. Ctrl+D to exit.")
    interp = HSLInterpreter()
    env = HSLEnvironment(parent=interp.global_env)
    while True:
        try:
            line = input("hsl> ")
            if not line.strip(): continue
            result = interp.run_source(line, env)
            if result is not None:
                print(f"  => {result}")
        except EOFError:
            print()
            break
        except KeyboardInterrupt:
            print()
            continue
        except Exception as e:
            print(f"  Error: {e}")


# ============================================================
# Main
# ============================================================

if __name__ == '__main__':
    if len(sys.argv) < 2:
        repl()
    else:
        cmd = sys.argv[1]
        interp = HSLInterpreter()
        if cmd == '--repl':
            repl()
        elif cmd == '--run' and len(sys.argv) >= 3:
            interp.run_file(sys.argv[2])
        elif cmd == '--dir' and len(sys.argv) >= 3:
            interp.run_directory(sys.argv[2])
        elif cmd == '--eval' and len(sys.argv) >= 3:
            print(interp.run_source(sys.argv[2]))
        elif cmd == '--help':
            print("HSL - Havok Scripting Library Interpreter v1.0")
            print("")
            print("Usage: hsl [command] [args]")
            print("")
            print("Commands:")
            print("  (no args)       Start interactive REPL")
            print("  --repl          Start interactive REPL")
            print("  --run <file>    Execute an .hsl file")
            print("  --dir <dir>     Execute all .hsl files in a directory")
            print("  --eval <code>   Evaluate HSL code string")
            print("  --help          Show this help")
        else:
            interp.run_file(sys.argv[1])
