ENV["BASIC_USER"] = "mrssporty"
ENV["BASIC_PASS"] = "roastbeef"
bind "unix://#{File.expand_path(File.dirname(__FILE__))}/puma.socket"
threads 48,48
workers 1
