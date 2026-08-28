json.agent_id @agent.id
json.permission_profile_id @account_user.permission_profile_id
json.inboxes @memberships do |membership|
  json.inbox_id membership.inbox_id
  json.inbox_name membership.inbox.name
  json.permission_profile_id membership.permission_profile_id
end
