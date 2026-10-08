package limiter

import (
	"context"
	"io"

	"github.com/xtls/xray-core/common"
	"github.com/xtls/xray-core/common/buf"
	"golang.org/x/time/rate"
)

type Writer struct {
	writer  buf.Writer
	limiter *rate.Limiter
	w       io.Writer
}

func (l *Limiter) RateWriter(writer buf.Writer, limiter *rate.Limiter) buf.Writer {
	return &Writer{
		writer:  writer,
		limiter: limiter,
	}
}

func (w *Writer) Close() error {
	return common.Close(w.writer)
}

func (w *Writer) WriteMultiBuffer(mb buf.MultiBuffer) error {
	waitN(w.limiter, int(mb.Len()))
	return w.writer.WriteMultiBuffer(mb)
}

// waitN blocks until n bytes are allowed. rate.Limiter.WaitN fails immediately
// (without waiting) when n exceeds the burst, which happened for low limits, so
// wait in burst-sized chunks.
func waitN(l *rate.Limiter, n int) {
	burst := l.Burst()
	if burst <= 0 {
		return
	}
	for n > 0 {
		c := n
		if c > burst {
			c = burst
		}
		_ = l.WaitN(context.Background(), c)
		n -= c
	}
}

// Reader rate-limits a buf.Reader. It is used for links handed over through
// DispatchLink (e.g. VLESS), where the uplink is a reader instead of a pipe writer.
type Reader struct {
	reader  buf.Reader
	limiter *rate.Limiter
}

func (l *Limiter) RateReader(reader buf.Reader, limiter *rate.Limiter) buf.Reader {
	return &Reader{
		reader:  reader,
		limiter: limiter,
	}
}

func (r *Reader) ReadMultiBuffer() (buf.MultiBuffer, error) {
	mb, err := r.reader.ReadMultiBuffer()
	waitN(r.limiter, int(mb.Len()))
	return mb, err
}

func (r *Reader) Interrupt() {
	common.Interrupt(r.reader)
}

func (r *Reader) Close() error {
	return common.Close(r.reader)
}
