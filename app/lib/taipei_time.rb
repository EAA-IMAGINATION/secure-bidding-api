# frozen_string_literal: true

module SecureBidding
  # Taiwan (UTC+8) is the course/demo timezone. Normalize naive form values here
  # so API storage and bidding_closed? checks use the same instant everywhere.
  module TaipeiTime
    OFFSET = '+08:00'
    DATETIME_LOCAL_PATTERN = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?\z/

    module_function

    def parse(value)
      str = value.to_s.strip
      return nil if str.empty?

      if (match = DATETIME_LOCAL_PATTERN.match(str))
        Time.new(
          match[1].to_i, match[2].to_i, match[3].to_i,
          match[4].to_i, match[5].to_i, (match[6] || 0).to_i,
          OFFSET
        )
      else
        Time.parse(str)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_deadline(value)
      parse(value)
    end
  end
end
