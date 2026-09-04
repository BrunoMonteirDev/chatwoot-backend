class Contacts::PhoneNumberNormalizer
  BRAZILIAN_MOBILE_WITH_NINTH_DIGIT = /\A\+55([1-9]\d)9(\d{8})\z/
  BRAZILIAN_NATIONAL_NUMBER = /\A[1-9]\d(?:9?\d{8})\z/

  def self.normalize(value)
    return if value.blank?

    input = value.to_s.strip
    return input unless input.match?(/\A[+\d\s().-]+\z/)

    digits = input.delete('^0-9')
    return input if digits.length < 7 || digits.length > 15

    international = if input.start_with?('+') || digits.start_with?('55')
                      "+#{digits}"
                    elsif BRAZILIAN_NATIONAL_NUMBER.match?(digits)
                      "+55#{digits}"
                    else
                      "+#{digits}"
                    end

    match = BRAZILIAN_MOBILE_WITH_NINTH_DIGIT.match(international)
    match ? "+55#{match[1]}#{match[2]}" : international
  end
end
