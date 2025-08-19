-- Stoa Protocol Database Schema Updates
-- This file contains recommended updates to align the database schema with the deployed smart contracts

-- Enable pgcrypto for gen_random_uuid
create extension if not exists pgcrypto;

-- USERS TABLE
-- Enhanced to match protocol features
create table users (
  wallet text primary key,
  username text,
  pfp text,
  reputation float default 0,
  joined_at timestamptz default now(),
  total_questions_created integer default 0,
  total_answers_submitted integer default 0,
  total_rewards_earned bigint default 0,
  total_fees_earned bigint default 0, -- Creator fees earned
  last_activity timestamptz default now()
);

-- QUESTIONS TABLE  
-- Updated to match StoaQuestion contract structure
create table questions (
  id uuid primary key default gen_random_uuid(),
  question_id bigint unique not null, -- From contract questionCount
  contract_address text not null, -- Individual question contract address
  creator text not null references users(wallet),
  content text not null, -- The actual question content
  token_address text not null, -- ERC20 token used for fees/rewards
  submission_cost bigint not null,
  max_winners integer not null,
  duration integer not null, -- Duration in seconds
  evaluator text not null, -- Address authorized to evaluate
  start_time timestamptz not null,
  end_time timestamptz not null,
  evaluation_deadline timestamptz not null,
  seeded_amount bigint default 0, -- Amount seeded by funders
  total_reward_pool bigint default 0, -- Available for distribution
  total_submissions integer default 0,
  protocol_fees_collected bigint default 0,
  creator_fees_collected bigint default 0,
  status text default 'active' check (status in ('active', 'ended', 'evaluated', 'emergency')),
  evaluated_at timestamptz,
  creation_tx_hash text,
  evaluation_tx_hash text
);

-- ANSWERS TABLE
-- Updated to match contract Answer struct
create table answers (
  id uuid primary key default gen_random_uuid(),
  answer_index bigint not null, -- Index in contract answers array
  question_id bigint references questions(question_id) on delete cascade,
  contract_address text not null, -- Question contract address
  responder text not null references users(wallet),
  answer_hash text not null, -- Keccak256 hash stored on-chain
  content text not null, -- Full answer content (off-chain)
  timestamp timestamptz not null, -- Submission timestamp
  score integer default 0, -- Score assigned during evaluation (0 = no score)
  rank integer, -- Final ranking (1 = best, 2 = second, etc.)
  reward_amount bigint default 0, -- Amount claimed as reward
  rewarded boolean default false, -- Has reward been claimed
  submission_tx_hash text,
  reward_claim_tx_hash text,
  created_at timestamptz default now()
);

-- EVALUATIONS TABLE
-- New table to track evaluation events
create table evaluations (
  id uuid primary key default gen_random_uuid(),
  question_id bigint references questions(question_id) on delete cascade,
  evaluator text not null,
  ranked_answer_indices bigint[], -- Array of answer indices in ranking order
  total_score integer not null, -- Sum of all scores assigned
  evaluation_tx_hash text not null,
  evaluated_at timestamptz default now(),
  ai_evaluation_data jsonb -- Store AI evaluation reasoning/metadata
);

-- SEEDS TABLE  
-- Track question seeding events
create table seeds (
  id uuid primary key default gen_random_uuid(),
  question_id bigint references questions(question_id) on delete cascade,
  funder text not null references users(wallet),
  amount bigint not null,
  tx_hash text not null,
  seeded_at timestamptz default now()
);

-- REWARD_CLAIMS TABLE
-- Track individual reward claim events
create table reward_claims (
  id uuid primary key default gen_random_uuid(),
  question_id bigint references questions(question_id) on delete cascade,
  answer_id uuid references answers(id) on delete cascade,
  claimer text not null references users(wallet),
  amount bigint not null,
  tx_hash text not null,
  claimed_at timestamptz default now()
);

-- EMERGENCY_REFUNDS TABLE
-- Track emergency refund events
create table emergency_refunds (
  id uuid primary key default gen_random_uuid(),
  question_id bigint references questions(question_id) on delete cascade,
  user_wallet text not null references users(wallet),
  refund_amount bigint not null,
  tx_hash text not null,
  refunded_at timestamptz default now()
);

-- REPUTATION_HISTORY TABLE
-- Enhanced reputation tracking
create table reputation_history (
  id uuid primary key default gen_random_uuid(),
  wallet text references users(wallet),
  change float not null,
  new_total float not null,
  reason text not null, -- 'answer_scored', 'question_created', 'reward_claimed', etc.
  question_id bigint references questions(question_id),
  answer_id uuid references answers(id),
  tx_hash text,
  timestamp timestamptz default now()
);

-- AI_EVALUATIONS TABLE
-- Store AI evaluation process data
create table ai_evaluations (
  id uuid primary key default gen_random_uuid(),
  question_id bigint references questions(question_id) on delete cascade,
  ai_model text not null, -- Model used for evaluation
  evaluation_prompt text, -- Prompt sent to AI
  raw_response jsonb, -- Full AI response
  confidence_score float, -- AI confidence in evaluation
  processing_time_ms integer, -- Time taken to evaluate
  cost_usd float, -- API cost for evaluation
  status text default 'pending' check (status in ('pending', 'completed', 'failed', 'disputed')),
  error_message text,
  created_at timestamptz default now(),
  completed_at timestamptz
);

-- PROTOCOL_METRICS TABLE
-- Enhanced metrics tracking
create table protocol_metrics (
  id uuid primary key default gen_random_uuid(),
  date date not null unique,
  total_questions_created integer default 0,
  total_answers_submitted integer default 0,
  total_volume_tokens bigint default 0, -- Total tokens processed
  total_protocol_fees bigint default 0,
  total_creator_fees bigint default 0,
  total_rewards_distributed bigint default 0,
  unique_users integer default 0,
  active_questions integer default 0,
  completed_evaluations integer default 0,
  emergency_refunds_count integer default 0,
  emergency_refunds_amount bigint default 0,
  avg_answers_per_question float default 0,
  avg_time_to_evaluation_hours float default 0
);

-- CONTRACT_EVENTS TABLE
-- Track all contract events for debugging/auditing
create table contract_events (
  id uuid primary key default gen_random_uuid(),
  contract_address text not null,
  event_name text not null,
  block_number bigint not null,
  tx_hash text not null,
  event_data jsonb not null,
  processed boolean default false,
  created_at timestamptz default now()
);

-- INDEXES for performance
create index idx_questions_creator on questions(creator);
create index idx_questions_status on questions(status);
create index idx_questions_end_time on questions(end_time);
create index idx_answers_question_id on answers(question_id);
create index idx_answers_responder on answers(responder);
create index idx_answers_score on answers(score);
create index idx_evaluations_question_id on evaluations(question_id);
create index idx_seeds_question_id on seeds(question_id);
create index idx_seeds_funder on seeds(funder);
create index idx_reward_claims_question_id on reward_claims(question_id);
create index idx_reputation_history_wallet on reputation_history(wallet);
create index idx_contract_events_processed on contract_events(processed);
create index idx_contract_events_block on contract_events(block_number);

-- Enable row-level security
alter table users enable row level security;
alter table questions enable row level security;
alter table answers enable row level security;
alter table evaluations enable row level security;
alter table seeds enable row level security;
alter table reward_claims enable row level security;
alter table emergency_refunds enable row level security;
alter table reputation_history enable row level security;
alter table ai_evaluations enable row level security;
alter table protocol_metrics enable row level security;
alter table contract_events enable row level security;

-- Trigger function to calculate question times
create or replace function set_question_times()
returns trigger as $$
begin
  new.end_time = new.start_time + make_interval(secs => new.duration);
  new.evaluation_deadline = new.start_time + make_interval(secs => new.duration) + interval '7 days';
  return new;
end;
$$ language plpgsql;

-- Trigger to automatically set times
create trigger set_question_times_trigger
  before insert or update of start_time, duration on questions
  for each row execute function set_question_times();

-- Default policies (service role only - update as needed for your app)
create policy "Service role access" on users for all using (auth.role() = 'service_role');
create policy "Service role access" on questions for all using (auth.role() = 'service_role');
create policy "Service role access" on answers for all using (auth.role() = 'service_role');
create policy "Service role access" on evaluations for all using (auth.role() = 'service_role');
create policy "Service role access" on seeds for all using (auth.role() = 'service_role');
create policy "Service role access" on reward_claims for all using (auth.role() = 'service_role');
create policy "Service role access" on emergency_refunds for all using (auth.role() = 'service_role');
create policy "Service role access" on reputation_history for all using (auth.role() = 'service_role');
create policy "Service role access" on ai_evaluations for all using (auth.role() = 'service_role');
create policy "Service role access" on protocol_metrics for all using (auth.role() = 'service_role');
create policy "Service role access" on contract_events for all using (auth.role() = 'service_role');

-- Example public read policies (uncomment and modify as needed)
-- create policy "Public read access" on questions for select using (true);
-- create policy "Public read access" on answers for select using (true);
-- create policy "Users can read own data" on users for select using (auth.uid()::text = wallet);

-- VIEWS for common queries
create view question_stats as
select 
  q.question_id,
  q.contract_address,
  q.creator,
  q.status,
  q.total_submissions,
  q.total_reward_pool,
  q.seeded_amount,
  q.start_time,
  q.end_time,
  q.evaluation_deadline,
  coalesce(e.evaluated_at, null) as evaluated_at,
  case 
    when now() > q.evaluation_deadline and q.status != 'evaluated' then true
    else false
  end as emergency_refund_available
from questions q
left join evaluations e on q.question_id = e.question_id;

create view user_stats as
select 
  u.wallet,
  u.username,
  u.reputation,
  u.total_questions_created,
  u.total_answers_submitted,
  u.total_rewards_earned,
  u.total_fees_earned,
  coalesce(avg(a.score), 0) as avg_answer_score,
  count(distinct q.question_id) as active_questions,
  u.last_activity
from users u
left join questions q on u.wallet = q.creator and q.status in ('active', 'ended')
left join answers a on u.wallet = a.responder and a.score > 0
group by u.wallet, u.username, u.reputation, u.total_questions_created, 
         u.total_answers_submitted, u.total_rewards_earned, u.total_fees_earned, u.last_activity;