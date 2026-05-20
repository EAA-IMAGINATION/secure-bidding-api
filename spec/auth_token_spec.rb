# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'time'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'SecureBidding::AuthToken' do
  before do
    # Generate a new key for each test to ensure isolation
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
  end

  describe 'Time constants' do
    it 'defines ONE_HOUR constant' do
      _(SecureBidding::AuthToken::ONE_HOUR).must_equal 3600
    end

    it 'defines ONE_DAY constant' do
      _(SecureBidding::AuthToken::ONE_DAY).must_equal 86_400
    end

    it 'defines ONE_WEEK constant' do
      _(SecureBidding::AuthToken::ONE_WEEK).must_equal 604_800
    end

    it 'defines ONE_MONTH constant' do
      _(SecureBidding::AuthToken::ONE_MONTH).must_equal 2_592_000
    end

    it 'defines ONE_YEAR constant' do
      _(SecureBidding::AuthToken::ONE_YEAR).must_equal 31_536_000
    end
  end

  describe 'Error classes' do
    it 'defines ExpiredTokenError' do
      _(SecureBidding::ExpiredTokenError).must_be_kind_of Class
      _(SecureBidding::ExpiredTokenError.superclass).must_equal StandardError
    end

    it 'defines InvalidTokenError' do
      _(SecureBidding::InvalidTokenError).must_be_kind_of Class
      _(SecureBidding::InvalidTokenError.superclass).must_equal StandardError
    end
  end

  describe 'setup' do
    it 'configures the encryption key from Base64-encoded string' do
      key = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key)
      
      # Test that encryption works (no error raised)
      token = SecureBidding::AuthToken.new('test payload')
      _(token.to_s).wont_be_nil
      _(token.to_s).must_be_kind_of String
    end
  end

  describe 'Token creation with default expiration' do
    it 'creates a token with default ONE_WEEK expiration' do
      payload = { account_id: '123', username: 'alice' }
      token = SecureBidding::AuthToken.new(payload)
      
      _(token.fresh?).must_equal true
      _(token.payload).must_equal payload
    end

    it 'sets expiration to roughly now + ONE_WEEK' do
      now = Time.now.to_i
      token = SecureBidding::AuthToken.new({ data: 'test' })
      
      expected_exp = now + SecureBidding::AuthToken::ONE_WEEK
      # Allow 2 seconds tolerance for test execution time
      _(token.instance_variable_get(:@expiration)).must_be :>=, expected_exp - 2
      _(token.instance_variable_get(:@expiration)).must_be :<=, expected_exp + 2
    end
  end

  describe 'Token creation with custom expiration' do
    it 'creates a token with custom ONE_HOUR expiration' do
      payload = { user: 'bob' }
      token = SecureBidding::AuthToken.new(payload, SecureBidding::AuthToken::ONE_HOUR)
      
      _(token.fresh?).must_equal true
      _(token.payload).must_equal payload
    end

    it 'creates a token with ONE_DAY expiration' do
      token = SecureBidding::AuthToken.new({ role: 'admin' }, SecureBidding::AuthToken::ONE_DAY)
      _(token.fresh?).must_equal true
    end

    it 'sets expiration to now + custom duration' do
      now = Time.now.to_i
      custom_duration = 7200  # 2 hours
      token = SecureBidding::AuthToken.new({ data: 'test' }, custom_duration)
      
      expected_exp = now + custom_duration
      _(token.instance_variable_get(:@expiration)).must_be :>=, expected_exp - 2
      _(token.instance_variable_get(:@expiration)).must_be :<=, expected_exp + 2
    end
  end

  describe 'Tokenization' do
    it 'converts token to Base64 string' do
      payload = { account_id: '456' }
      token = SecureBidding::AuthToken.new(payload)
      token_string = token.to_s
      
      _(token_string).must_be_kind_of String
      _(token_string).wont_be_empty
      _(token_string).must_match(/\A[A-Za-z0-9+\/=]+\z/)  # Base64 pattern
    end

    it 'can tokenize with class method' do
      payload = { user: 'charlie' }
      token_string = SecureBidding::AuthToken.tokenize(payload)
      
      _(token_string).must_be_kind_of String
      _(token_string).wont_be_empty
    end

    it 'can tokenize with custom expiration' do
      payload = { data: 'secret' }
      token_string = SecureBidding::AuthToken.tokenize(
        payload,
        SecureBidding::AuthToken::ONE_HOUR
      )
      
      _(token_string).must_be_kind_of String
    end
  end

  describe 'Detokenization' do
    it 'decrypts and parses a valid token' do
      payload = { account_id: '789', name: 'Dave' }
      token = SecureBidding::AuthToken.new(payload)
      token_string = token.to_s
      
      decrypted = SecureBidding::AuthToken.detokenize(token_string)
      
      _(decrypted).must_be_kind_of Hash
      _(decrypted[:payload]).must_equal payload
      _(decrypted[:exp]).must_be_kind_of Integer
    end

    it 'raises InvalidTokenError for corrupted ciphertext' do
      bad_token = 'not_a_valid_base64_or_too_short=='
      
      _(proc {
        SecureBidding::AuthToken.detokenize(bad_token)
      }).must_raise SecureBidding::InvalidTokenError
    end

    it 'raises InvalidTokenError for invalid Base64' do
      bad_token = 'Not valid Base64 at all!'
      
      _(proc {
        SecureBidding::AuthToken.detokenize(bad_token)
      }).must_raise SecureBidding::InvalidTokenError
    end

    it 'raises InvalidTokenError if JSON parsing fails' do
      # Create a valid Base64 string that decrypts to invalid JSON
      key = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key)
      
      # Manually create a corrupted token by encrypting invalid JSON
      encrypted = SecureBidding::AuthToken.encrypt('not valid json')
      
      _(proc {
        SecureBidding::AuthToken.detokenize(encrypted)
      }).must_raise SecureBidding::InvalidTokenError
    end
  end

  describe 'Token loading' do
    it 'loads a token from token string' do
      payload = { user_id: '111' }
      original_token = SecureBidding::AuthToken.new(payload)
      token_string = original_token.to_s
      
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token).must_be_kind_of SecureBidding::AuthToken
      _(loaded_token.payload).must_equal payload
    end

    it 'raises InvalidTokenError when loading corrupted token' do
      bad_token = 'invalid_token_string'
      
      _(proc {
        SecureBidding::AuthToken.load(bad_token)
      }).must_raise SecureBidding::InvalidTokenError
    end
  end

  describe 'Payload access' do
    it 'returns payload when token is fresh' do
      payload = { session: 'active' }
      token = SecureBidding::AuthToken.new(payload)
      
      _(token.payload).must_equal payload
    end

    it 'returns payload multiple times without issue' do
      payload = { counter: 0 }
      token = SecureBidding::AuthToken.new(payload)
      
      _(token.payload).must_equal payload
      _(token.payload).must_equal payload  # Call twice
    end

    it 'raises ExpiredTokenError when accessing expired token payload' do
      # Create token with -1 second expiration (already expired)
      token = SecureBidding::AuthToken.new({ data: 'secret' }, -1)
      
      _(proc {
        token.payload
      }).must_raise SecureBidding::ExpiredTokenError
    end

    it 'error message for expired token is clear' do
      token = SecureBidding::AuthToken.new({ data: 'test' }, -1)
      
      begin
        token.payload
      rescue SecureBidding::ExpiredTokenError => e
        _(e.message).must_include 'Token has expired'
      end
    end
  end

  describe 'Expiration checking' do
    it 'expired? returns false for fresh token' do
      token = SecureBidding::AuthToken.new({ data: 'test' })
      _(token.expired?).must_equal false
    end

    it 'expired? returns true for expired token' do
      # -1 second = expired 1 second ago
      token = SecureBidding::AuthToken.new({ data: 'test' }, -1)
      _(token.expired?).must_equal true
    end

    it 'expired? returns false for token expiring in future' do
      token = SecureBidding::AuthToken.new({ data: 'test' }, 3600)
      _(token.expired?).must_equal false
    end

    it 'fresh? returns true for fresh token' do
      token = SecureBidding::AuthToken.new({ data: 'test' })
      _(token.fresh?).must_equal true
    end

    it 'fresh? returns false for expired token' do
      token = SecureBidding::AuthToken.new({ data: 'test' }, -1)
      _(token.fresh?).must_equal false
    end

    it 'raises InvalidTokenError if expiration is not integer' do
      token = SecureBidding::AuthToken.new({ data: 'test' })
      token.instance_variable_set(:@expiration, 'not_an_integer')
      
      _(proc {
        token.expired?
      }).must_raise SecureBidding::InvalidTokenError
    end

    it 'error message for non-integer expiration is clear' do
      token = SecureBidding::AuthToken.new({ data: 'test' })
      token.instance_variable_set(:@expiration, 3.14)
      
      begin
        token.expired?
      rescue SecureBidding::InvalidTokenError => e
        _(e.message).must_include 'not an integer'
      end
    end
  end

  describe 'Round-trip encryption/decryption' do
    it 'survives full round-trip: create -> tokenize -> detokenize -> load' do
      payload = {
        account_id: '999',
        username: 'eve',
        roles: ['admin', 'user']
      }
      
      # Create and tokenize
      token1 = SecureBidding::AuthToken.new(payload)
      token_string = token1.to_s
      
      # Detokenize
      decrypted_data = SecureBidding::AuthToken.detokenize(token_string)
      _(decrypted_data[:payload]).must_equal payload
      
      # Load and verify
      token2 = SecureBidding::AuthToken.load(token_string)
      _(token2.payload).must_equal payload
      _(token2.fresh?).must_equal true
    end

    it 'preserves complex nested payload through round-trip' do
      payload = {
        account: {
          id: '123',
          email: 'user@example.com',
          profile: {
            name: 'Frank',
            age: 30
          }
        },
        permissions: ['read', 'write', 'delete']
      }
      
      token_string = SecureBidding::AuthToken.tokenize(payload)
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token.payload).must_equal payload
    end

    it 'handles array payloads' do
      payload = ['item1', 'item2', 'item3']
      token_string = SecureBidding::AuthToken.tokenize(payload)
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token.payload).must_equal payload
    end

    it 'handles string payloads' do
      payload = 'simple string payload'
      token_string = SecureBidding::AuthToken.tokenize(payload)
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token.payload).must_equal payload
    end

    it 'handles numeric payloads' do
      payload = 42
      token_string = SecureBidding::AuthToken.tokenize(payload)
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token.payload).must_equal payload
    end
  end

  describe 'Different keys produce different tokens' do
    it 'same payload with different keys produces different token strings' do
      payload = { data: 'secret' }
      
      # First key
      key1 = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key1)
      token_string1 = SecureBidding::AuthToken.tokenize(payload)
      
      # Second key
      key2 = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key2)
      token_string2 = SecureBidding::AuthToken.tokenize(payload)
      
      _(token_string1).wont_equal token_string2
    end

    it 'token encrypted with key1 cannot be decrypted with key2' do
      payload = { secret: 'information' }
      
      # Encrypt with key1
      key1 = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key1)
      token_string = SecureBidding::AuthToken.tokenize(payload)
      
      # Try to decrypt with key2
      key2 = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key2)
      
      _(proc {
        SecureBidding::AuthToken.detokenize(token_string)
      }).must_raise SecureBidding::InvalidTokenError
    end
  end

  describe 'Registration token use case (1 hour expiration)' do
    it 'creates registration token with ONE_HOUR expiration' do
      registration_payload = {
        email: 'newuser@example.com',
        registration_code: 'code123'
      }
      
      token = SecureBidding::AuthToken.new(
        registration_payload,
        SecureBidding::AuthToken::ONE_HOUR
      )
      
      _(token.fresh?).must_equal true
      _(token.payload).must_equal registration_payload
    end
  end

  describe 'Session token use case (1 week expiration)' do
    it 'creates session token with ONE_WEEK expiration' do
      session_payload = {
        account_id: 'user-456',
        authenticated_at: Time.now.to_i
      }
      
      token = SecureBidding::AuthToken.new(
        session_payload,
        SecureBidding::AuthToken::ONE_WEEK
      )
      
      _(token.fresh?).must_equal true
      _(token.payload).must_equal session_payload
    end
  end

  describe 'Edge cases' do
    it 'handles nil payload' do
      token = SecureBidding::AuthToken.new(nil)
      _(token.payload).must_be_nil
    end

    it 'handles empty hash payload' do
      token = SecureBidding::AuthToken.new({})
      _(token.payload).must_equal({})
    end

    it 'handles zero duration expiration' do
      # Zero duration means expire immediately
      token = SecureBidding::AuthToken.new({ data: 'test' }, 0)
      _(token.expired?).must_equal true
    end

    it 'handles very large expiration' do
      token = SecureBidding::AuthToken.new(
        { data: 'test' },
        SecureBidding::AuthToken::ONE_YEAR * 10
      )
      _(token.fresh?).must_equal true
    end

    it 'handles unicode characters in payload' do
      payload = {
        greeting: '你好世界',
        emoji: '🔐',
        german: 'Äpfel'
      }
      
      token_string = SecureBidding::AuthToken.tokenize(payload)
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token.payload).must_equal payload
    end

    it 'handles special characters in strings' do
      payload = "String with special chars: !@#$%^&*()[]{}|\\;:'\",.<>?/~`"
      token_string = SecureBidding::AuthToken.tokenize(payload)
      loaded_token = SecureBidding::AuthToken.load(token_string)
      
      _(loaded_token.payload).must_equal payload
    end
  end

  describe 'Key generation' do
    it 'generates random keys' do
      key1 = SecureBidding::AuthToken.generate_key
      key2 = SecureBidding::AuthToken.generate_key
      
      _(key1).wont_equal key2
    end

    it 'generated keys are Base64 encoded' do
      key = SecureBidding::AuthToken.generate_key
      _(key).must_match(/\A[A-Za-z0-9+\/=]+\z/)
    end

    it 'can setup with generated key' do
      key = SecureBidding::AuthToken.generate_key
      SecureBidding::AuthToken.setup(key)
      
      token = SecureBidding::AuthToken.new({ test: 'data' })
      _(token.to_s).wont_be_nil
    end
  end
end
# rubocop:enable Metrics/BlockLength
