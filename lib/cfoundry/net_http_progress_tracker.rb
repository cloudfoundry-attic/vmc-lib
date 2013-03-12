module ProgressTracker
  attr_accessor :upload_progress_callback

  private

  def send_request_with_body_stream(sock, ver, path, f)
    unless content_length || chunked?
      raise ArgumentError, "Content-Length not given and Transfer-Encoding is not `chunked'"
    end

    @upload_size = 0 #WTF??? if @upload_size.nil?

    supply_default_content_type
    write_header(sock, ver, path)

    if chunked?
      while s = f.read(1024)
        @upload_size += s.length
        sock.write(sprintf("%x\r\n", s.length) << s << "\r\n")
      end
      sock.write("0\r\n\r\n")
    else
      while s = f.read(16 * 1024)
        @upload_size += s.length
        upload_progress_callback.call(@upload_size, content_length) if upload_progress_callback
        sock.write(s)
      end
    end
  end
end
