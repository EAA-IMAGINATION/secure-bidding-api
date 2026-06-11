# frozen_string_literal: true

module SecureBidding
  # OAuth-style authorization scope carried inside an AuthToken.
  class AuthScope
    ALL = '*'
    READ = 'read'
    WRITE = 'write'
    FULL = '*:write'
    READ_ONLY = '*:read'
    API_KEY_SCOPES = [
      READ_ONLY,
      FULL,
      'projects:read',
      'projects:write',
      'accounts:read'
    ].freeze

    SEPARATOR = ' '
    DIVIDER = ':'

    def initialize(scopes = FULL)
      @scopes_str = scopes.to_s
      @scopes = {}
      @scopes_str.split(SEPARATOR).each { |scope| add_scope(scope) }
    end

    def can_read?(resource)
      readable?(ALL) || readable?(resource)
    end

    def can_write?(resource)
      writeable?(ALL) || writeable?(resource)
    end

    def to_s
      @scopes_str
    end

    def self.api_key_scope_allowed?(scope_str)
      API_KEY_SCOPES.include?(scope_str.to_s.strip)
    end

    # True when every permission in this scope is allowed by grantor.
    def permitted_by?(grantor)
      grantor = grantor.is_a?(AuthScope) ? grantor : AuthScope.new(grantor)
      @scopes.all? do |resource, permissions|
        permissions.all? do |permission|
          case permission
          when WRITE then grantor.can_write?(resource)
          when READ then grantor.can_read?(resource)
          else false
          end
        end
      end
    end

    private

    def readable?(resource)
      writeable?(resource) || permission_granted?(resource, READ)
    end

    def writeable?(resource)
      permission_granted?(resource, WRITE)
    end

    def permission_granted?(resource, permission)
      @scopes[resource]&.include?(permission) || false
    end

    def add_scope(scope)
      resource, permission = scope.split(DIVIDER)
      return if resource.nil? || permission.nil?

      @scopes[resource] ||= []
      @scopes[resource] << permission
    end
  end
end
