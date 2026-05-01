class Webhooks::InstagramEventsJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  # @return [Array] We will support further events like reaction or seen in future
  SUPPORTED_EVENTS = [:message, :read].freeze

  def perform(entries)
    @entries = entries

    key = format(::Redis::Alfred::IG_MESSAGE_MUTEX, sender_id: contact_instagram_id, ig_account_id: ig_account_id)
    with_lock(key) do
      process_entries(entries)
    end
  end

  # https://developers.facebook.com/docs/messenger-platform/instagram/features/webhook
  def process_entries(entries)
    entries.each do |entry|
      process_single_entry(entry.with_indifferent_access)
    end
  end

  private

  def process_single_entry(entry)
    if test_event?(entry)
      process_test_event(entry)
      return
    end

    process_messages(entry)
  end

  def process_messages(entry)
    messages(entry).each do |messaging|
      Rails.logger.info("Instagram Events Job Messaging: #{messaging}")

      instagram_id = instagram_id(messaging)
      channel = find_channel(instagram_id)

      next if channel.blank?

      if (event_name = event_name(messaging))
        send(event_name, messaging, channel)
      end
    end
  end

  def agent_message_via_echo?(messaging)
    messaging[:message].present? && messaging[:message][:is_echo].present?
  end

  def test_event?(entry)
    entry[:changes].present?
  end

  # PATCH: Chatwoot natively drops Instagram comments (field: comments/live_comments).
  # This override detects real comment events and forwards them to n8n via WebhookJob,
  # while preserving the original TestEventService path for Meta's developer test events.
  def process_test_event(entry)
    changes = entry[:changes] || []
    changes.each do |change|
      field = change[:field].to_s
      value = change[:value]

      if field == 'comments' || field == 'live_comments'
        forward_comment_to_n8n(entry[:id], field, value)
      else
        # Meta test events for DMs use field "messages" with fixed sender/recipient IDs
        Instagram::TestEventService.new(value).perform if value.present?
      end
    end
  end

  def forward_comment_to_n8n(ig_account_id, field, value)
    n8n_url = ENV.fetch('INSTAGRAM_COMMENTS_N8N_WEBHOOK_URL', nil)
    return if n8n_url.blank?

    payload = {
      ig_account_id: ig_account_id,
      field: field,
      value: value,
      received_at: Time.now.utc.iso8601
    }

    WebhookJob.perform_later(n8n_url, payload)
  rescue StandardError => e
    Rails.logger.error("Failed to forward Instagram comment to n8n: #{e.message}")
  end

  def extract_messaging_from_test_event(entry)
    entry[:changes].first&.dig(:value) if entry[:changes].present?
  end

  def instagram_id(messaging)
    if agent_message_via_echo?(messaging)
      messaging[:sender][:id]
    else
      messaging[:recipient][:id]
    end
  end

  def ig_account_id
    @entries&.first&.dig(:id)
  end

  def contact_instagram_id
    entry = @entries&.first
    return nil unless entry

    messaging = (entry[:messaging].presence || entry[:standby] || []).first
    return nil unless messaging

    if messaging.dig(:message, :is_echo)
      messaging.dig(:recipient, :id)
    else
      messaging.dig(:sender, :id)
    end
  end

  def sender_id
    @entries&.dig(0, :messaging, 0, :sender, :id)
  end

  def find_channel(instagram_id)
    channel = Channel::Instagram.find_by(instagram_id: instagram_id)
    channel ||= Channel::FacebookPage.find_by(instagram_id: instagram_id)
    channel
  end

  def event_name(messaging)
    @event_name ||= SUPPORTED_EVENTS.find { |key| messaging.key?(key) }
  end

  def message(messaging, channel)
    if channel.is_a?(Channel::Instagram)
      ::Instagram::MessageText.new(messaging, channel).perform
    else
      ::Instagram::Messenger::MessageText.new(messaging, channel).perform
    end
  end

  def read(messaging, channel)
    ::Instagram::ReadStatusService.new(params: messaging, channel: channel).perform
  end

  def messages(entry)
    (entry[:messaging].presence || entry[:standby] || [])
  end
end
