"""A visitor for ANDTLR notation ASTs, producing plain text with ellipses.

Somewhat-closely approximates the rendering of the original manual.
"""

from io import StringIO

from .parsing import parse
from .TacticNotationsParser import TacticNotationsParser
from .TacticNotationsVisitor import TacticNotationsVisitor

class TacticNotationsToDotsVisitor(TacticNotationsVisitor):
    def __init__(self):
        self.buffer = StringIO()

    def visitRepeat(self, ctx:TacticNotationsParser.RepeatContext):
        separator = ctx.ATOM()
        self.visitChildren(ctx)
        if ctx.LGROUP().getText()[1] == "+":
            spacer = (separator.getText() + " " if separator else "")
            self.buffer.write(spacer + "…" + spacer)
            self.visitChildren(ctx)

    def visitCurlies(self, ctx:TacticNotationsParser.CurliesContext):
        self.buffer.write("{")
        self.visitChildren(ctx)
        self.buffer.write("}")

    def visitAtomic(self, ctx:TacticNotationsParser.AtomicContext):
        self.buffer.write(ctx.ATOM().getText())

    def visitHole(self, ctx:TacticNotationsParser.HoleContext):
        self.buffer.write("‘{}’".format(ctx.ID().getText()[1:]))

    def visitMeta(self, ctx:TacticNotationsParser.MetaContext):
        self.buffer.write(ctx.METACHAR().getText()[1:])

    def visitWhitespace(self, ctx:TacticNotationsParser.WhitespaceContext):
        self.buffer.write(" ")

def stringify_with_ellipses(notation):
    vs = TacticNotationsToDotsVisitor()
    vs.visit(parse(notation))
    return vs.buffer.getvalue()
