interface Token {
  text: string;
  color: string;
}

interface BashRule {
  reg: RegExp;
  color: string;
}

@Component
export struct CodeBlock {
  @Prop code: string;
  @Prop paddingTop: number = 16;
  @Prop paddingBottom: number = 16;

  private tokenizeBash(input: string): Token[] {
    const result: Token[] = [];
    const bashRules: BashRule[] = [
      { reg: /^#.*/, color: '#6A9955' },
      { reg: /^"[^"]*"/, color: '#CE9178' },
      { reg: /^'[^']*'/, color: '#CE9178' },
      { reg: /^\$\{[^}]*\}/, color: '#569CD6' },
      { reg: /^\$\w+/, color: '#569CD6' },
      { reg: /^(curl|jq|printf|export|set|unset|if|then|fi|for|while)\b/, color: '#4FC1FF' },
      { reg: /^--[a-zA-Z-]+/, color: '#9CDCFE' },
      { reg: /^[a-zA-Z_]\w*/, color: '#9CDCFE' },
      { reg: /^(\(|\)|\||=)/, color: '#DCDCAA' },
      { reg: /^\s+/, color: '#DCDCDC' },
      { reg: /^./, color: '#DCDCDC' }
    ];

    let rest: string = input;
    while (rest.length > 0) {
      let matched: boolean = false;
      for (const rule of bashRules) {
        const match: RegExpExecArray | null = rule.reg.exec(rest);
        if (match && match.index === 0) {
          result.push({ text: match[0], color: rule.color });
          rest = rest.substring(match[0].length);
          matched = true;
          break;
        }
      }
      if (!matched) {
        result.push({ text: rest[0], color: '#DCDCDC' });
        rest = rest.substring(1);
      }
    }
    return result;
  }

  build() {
    Column() {
      Scroll() {
        Text() {
          // Key 包含整段代码，切换服务或方法后全部重建，避免复用旧 Span 留下残影。
          ForEach(this.tokenizeBash(this.code), (item: Token, index: number) => {
            Span(item.text)
              .fontColor(item.color)
              .fontFamily('monospace')
              .fontSize(14)
          }, (item: Token, index: number) => `${this.code}:${index}`)
        }
          .fontFamily('monospace')
          .lineHeight(20)
          .fontSize(14)
          .maxLines(1000)
          .textOverflow({ overflow: TextOverflow.None })
          // 留出正文与横向滚动条之间的空间，而不是把间距加到 Scroll 外侧。
          .padding({ bottom: this.paddingBottom })
      }
      .scrollable(ScrollDirection.Horizontal)
    }
    .width("100%")
    .backgroundColor("#1E1E1E")
    .borderRadius(8)
    .padding({
      top: this.paddingTop,
      left: 10,
      right: 10,
      bottom: 8
    })
  }
}
