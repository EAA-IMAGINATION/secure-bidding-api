# frozen_string_literal: true

module SecureBidding
  # Shared helpers for dry-validation form results in route handlers.
  module FormValidation
    def self.response_for(app, result)
      return nil if result.success?

      app.response.status = 400
      errors = result.errors.to_h
      { error: normalize_errors(errors) }
    end

    def self.normalize_errors(errors)
      return errors unless errors.is_a?(Hash)
      return errors[''].first if errors.keys == [''] && errors[''].is_a?(Array) && errors[''].length == 1

      if errors.size == 1
        _field, messages = errors.first
        return messages.first if messages.is_a?(Array) && messages.length == 1
      end

      errors
    end
  end
end
