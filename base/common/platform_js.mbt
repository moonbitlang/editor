///|
/// `process.platform` when available (Node), otherwise the
/// `navigator.userAgent` browser sniff Monaco uses (`platform.ts`'s
/// `isMacintosh = _userAgent.indexOf('Macintosh') >= 0` family). `0` when
/// neither exists.
extern "js" fn detect_platform_code() -> Int =
  #| () => {
  #|   if (typeof process !== "undefined" && process.platform) {
  #|     if (process.platform === "darwin") return 1;
  #|     if (process.platform === "win32") return 2;
  #|     return 3;
  #|   }
  #|   if (typeof navigator !== "undefined" && navigator.userAgent) {
  #|     const userAgent = navigator.userAgent;
  #|     if (userAgent.indexOf("Macintosh") >= 0) return 1;
  #|     if (userAgent.indexOf("Windows") >= 0) return 2;
  #|     if (userAgent.indexOf("Linux") >= 0) return 3;
  #|   }
  #|   return 0;
  #| }
