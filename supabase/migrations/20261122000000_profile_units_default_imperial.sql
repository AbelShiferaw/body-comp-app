-- New users see pounds and feet/inches by default (US launch); they can
-- switch to kg and cm in Settings. Existing rows keep their choice.
alter table public.profiles
  alter column units set default 'imperial';
