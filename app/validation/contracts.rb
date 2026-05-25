# frozen_string_literal: true

require 'dry-validation'

module SecureBidding
  module Validation
    # Contract for creating projects
    class CreateProject < Dry::Validation::Contract
      params do
        required(:title).filled(:string)
        required(:budget_cents).filled(:integer, gt?: 0)
        optional(:state).value(included_in?: %w[saved published])
        optional(:submission_deadline_at).maybe(:string)
      end
    end

    # Contract for updating projects
    class UpdateProject < Dry::Validation::Contract
      params do
        optional(:title).filled(:string)
        optional(:budget_cents).filled(:integer, gt?: 0)
        optional(:state).value(included_in?: %w[saved published])
        optional(:submission_deadline_at).maybe(:string)
      end
    end

    # Contract for creating bid submissions
    class CreateBidSubmission < Dry::Validation::Contract
      params do
        required(:project_id).filled(:string)
        required(:contractor_alias).filled(:string)
        required(:plaintext_bid).filled(:string)
      end
    end

    # Contract for initial user registration
    class RegisterAccount < Dry::Validation::Contract
      params do
        required(:username).filled(:string)
        required(:email).filled(:string, format?: /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
      end
    end

    # Contract for verifying registration and choosing a password
    class VerifyAccount < Dry::Validation::Contract
      params do
        required(:registration_token).filled(:string)
        required(:password).filled(:string, min_size?: 8)
      end
    end
  end
end
