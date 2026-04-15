begin
  require 'hirb'
  Hirb.enable
rescue LoadError
  warn 'hirb is not installed; run bundle install to enable table formatting in pry.'
end
