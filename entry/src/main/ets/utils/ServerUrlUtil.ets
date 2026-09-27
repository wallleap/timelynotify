/** 从服务器地址提取 host[:port]，供服务切换列表显示无名称的服务器。 */
export function extractHost(url: string): string {
  let s: string = url;
  const protoEnd: number = s.indexOf('://');
  if (protoEnd >= 0) {
    s = s.substring(protoEnd + 3);
  }
  const slashIdx: number = s.indexOf('/');
  if (slashIdx >= 0) {
    s = s.substring(0, slashIdx);
  }
  return s;
}
