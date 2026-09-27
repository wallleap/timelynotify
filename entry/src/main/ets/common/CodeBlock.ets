// 先定义接口，ArkTS强制要求
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
  @Prop lang: string = "bash";
  @Prop paddingTop: number = 16;
  @Prop paddingBottom: number = 16;
  @State tokens: Token[] = [];

  aboutToAppear() {
    this.tokens = this.tokenizeBash(this.code);
  }

  tokenizeBash(input: string): Token[] {
    const result: Token[] = [];

    // 显式标注 BashRule[]
    const bashRules: BashRule[] = [
      { reg: /^[a-zA-Z_]\w*/, color: "#9CDCFE" }, // 标识符 seg1 seg2 echo
      { reg: /^#.*/, color: "#6A9955" }, //注释
      { reg: /^"[^"]*"/, color: "#CE9178" }, //双引号字符串
      { reg: /^'[^']*'/, color: "#CE9178" }, //单引号字符串
      { reg: /^\$\{[^}]*\}/, color: "#569CD6" }, // ${var}
      { reg: /^\$\w+/, color: "#569CD6" }, // $var
      { reg: /^(echo|curl|jq|export|set|unset|if|then|fi|for|while)/, color: "#4FC1FF" },
      { reg: /^(\(|\)|\||=)/, color: "#DCDCAA" },
      { reg: /^\s+/, color: "#DCDCDC" },
      { reg: /^./, color: "#DCDCDC" },// 修改兜底：单次1字符，禁止非贪婪.+?
    ];

    let rest: string = input;
    while (rest.length > 0) {
      let matched: boolean = false;
      for (const rule of bashRules) {
        const m: RegExpExecArray | null = rule.reg.exec(rest);
        if (m && m.index === 0) {
          result.push({ text: m[0], color: rule.color });
          rest = rest.substring(m[0].length);
          matched = true;
          break;
        }
      }
      if (!matched) {
        result.push({ text: rest[0], color: "#DCDCDC" });
        rest = rest.substring(1);
      }
    }
    return result;
  }

  build() {
    Column() {
      Scroll() {
        Text() {
          // 修复ForEach Key重复问题，使用index作为key，防止渲染错乱
          ForEach(this.tokens, (item: Token, index: number) => {
            Span(item.text)
              .fontColor(item.color)
              .fontFamily("monospace")
              .fontSize(14)
          }, (item: Token, index: number) => index.toString())
        }
        .fontFamily("monospace")
        .lineHeight(20)
        .fontSize(14)
        .maxLines(1000)
        .textOverflow({ overflow: TextOverflow.None })
      }
      .scrollable(ScrollDirection.Horizontal)
      .padding({ bottom: this.paddingBottom })
    }
    .width("100%")
    .backgroundColor("#1E1E1E")
    .borderRadius(8)
    .padding({
      top: this.paddingTop,
      left: 10,
      right: 10,
      bottom: 4
    })
  }
}
