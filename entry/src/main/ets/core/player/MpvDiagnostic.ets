/** Emit a fixed vocabulary, never raw URLs, headers, tickets or response bodies. */
export class MpvDiagnostic {
  static stage(prefix: string, text: string = ''): string {
    if (/demux|lavf/i.test(prefix)) return 'demux'
    if (/^vd\b|decoder|codec/i.test(prefix)) return 'decoder'
    if (/^vo\b|gpu/i.test(prefix)) return 'video_output'
    if (/stream|network|tcp|tls|http/i.test(prefix) || /ffmpeg/i.test(prefix) && /\bhttp\b|\bRange:|TLS|SSL|connection/i.test(text)) return 'network'
    if (/cplayer/i.test(prefix)) return 'player'
    return 'other'
  }

  static summary(text: string): string {
    const fields: string[] = []
    const status = text.match(/\bHTTP\/[\d.]+\s+([1-5]\d{2})\b/i) ?? text.match(/\bHTTP error\s+([1-5]\d{2})\b/i)
    if (status !== null) fields.push('http_status=' + status[1])
    const range = text.match(/\bRange:\s*bytes=(\d{1,20}-\d{0,20})(?=\s|$)/i)
    if (range !== null) fields.push('range=' + range[1])
    if (/\bGET\s+\//.test(text)) fields.push('event=request')
    if (/\b(?:connect|connection|connecting|connected)\b/i.test(text)) fields.push('event=connection')
    if (/\b(?:TLS|SSL|certificate)\b/i.test(text)) fields.push('event=tls')
    if (/timed? ?out|timeout/i.test(text)) fields.push('issue=timeout')
    if (/forbidden|unauthorized|access denied/i.test(text)) fields.push('issue=authorization')
    if (/failed|failure|error|invalid|unsupported|not found/i.test(text)) fields.push('issue=failure')
    if (/seek|seeking/i.test(text)) fields.push('event=seek')
    if (/Opening|opened|probing|detected/i.test(text)) fields.push('event=open_or_probe')
    if (/Using hardware decoding|Selected hwdec/i.test(text)) fields.push('event=hardware_decode')
    if (/\bVO:|video output|reconfig/i.test(text)) fields.push('event=video_output')
    return fields.join(' ')
  }
}
