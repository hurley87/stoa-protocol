# Stoa Protocol Database Schema

This document describes the database schema for the Stoa Protocol application, designed to support AI-powered question evaluation and reward distribution.

## Core Tables

### Users
Stores user profiles and aggregate statistics.

```sql
users (
  wallet text PRIMARY KEY,
  username text,
  pfp text,
  reputation float DEFAULT 0,
  total_questions_created integer DEFAULT 0,
  total_answers_submitted integer DEFAULT 0,
  total_rewards_earned bigint DEFAULT 0,
  total_fees_earned bigint DEFAULT 0,
  last_activity timestamptz DEFAULT now()
)
```

### Questions
Tracks individual questions and their smart contract instances.

```sql
questions (
  id uuid PRIMARY KEY,
  question_id bigint UNIQUE NOT NULL,
  contract_address text NOT NULL,
  creator text REFERENCES users(wallet),
  token_address text NOT NULL,
  submission_cost bigint NOT NULL,
  max_winners integer NOT NULL,
  duration integer NOT NULL,
  evaluator text NOT NULL,
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  evaluation_deadline timestamptz NOT NULL,
  seeded_amount bigint DEFAULT 0,
  total_reward_pool bigint DEFAULT 0,
  total_submissions integer DEFAULT 0,
  protocol_fees_collected bigint DEFAULT 0,
  creator_fees_collected bigint DEFAULT 0,
  status text DEFAULT 'active'
)
```

### Answers
Stores submitted answers with onchain and off-chain data.

```sql
answers (
  id uuid PRIMARY KEY,
  answer_index bigint NOT NULL,
  question_id bigint REFERENCES questions(question_id),
  contract_address text NOT NULL,
  responder text REFERENCES users(wallet),
  answer_hash text NOT NULL,
  content text NOT NULL,
  score integer DEFAULT 0,
  rank integer,
  reward_amount bigint DEFAULT 0,
  rewarded boolean DEFAULT false
)
```

## AI Evaluation Tables

### AI Evaluations
Tracks the AI evaluation process for each question.

```sql
ai_evaluations (
  id uuid PRIMARY KEY,
  question_id bigint REFERENCES questions(question_id),
  ai_model text NOT NULL,
  evaluation_prompt text,
  raw_response jsonb,
  confidence_score float,
  processing_time_ms integer,
  cost_usd float,
  status text DEFAULT 'pending'
)
```

### Evaluations
Records the final evaluation results submitted to the blockchain.

```sql
evaluations (
  id uuid PRIMARY KEY,
  question_id bigint REFERENCES questions(question_id),
  evaluator text NOT NULL,
  ranked_answer_indices bigint[],
  total_score integer NOT NULL,
  evaluation_tx_hash text NOT NULL,
  ai_evaluation_data jsonb
)
```

## Transaction Tables

### Seeds
Tracks question funding events.

```sql
seeds (
  id uuid PRIMARY KEY,
  question_id bigint REFERENCES questions(question_id),
  funder text REFERENCES users(wallet),
  amount bigint NOT NULL,
  tx_hash text NOT NULL
)
```

### Reward Claims
Records individual reward claim transactions.

```sql
reward_claims (
  id uuid PRIMARY KEY,
  question_id bigint REFERENCES questions(question_id),
  answer_id uuid REFERENCES answers(id),
  claimer text REFERENCES users(wallet),
  amount bigint NOT NULL,
  tx_hash text NOT NULL
)
```

### Emergency Refunds
Tracks emergency refund claims when evaluations are delayed.

```sql
emergency_refunds (
  id uuid PRIMARY KEY,
  question_id bigint REFERENCES questions(question_id),
  user_wallet text REFERENCES users(wallet),
  refund_amount bigint NOT NULL,
  tx_hash text NOT NULL
)
```

## System Tables

### Contract Events
Stores blockchain events for synchronization.

```sql
contract_events (
  id uuid PRIMARY KEY,
  contract_address text NOT NULL,
  event_name text NOT NULL,
  block_number bigint NOT NULL,
  tx_hash text NOT NULL,
  event_data jsonb NOT NULL,
  processed boolean DEFAULT false
)
```

### Protocol Metrics
Daily aggregated protocol statistics.

```sql
protocol_metrics (
  date date PRIMARY KEY,
  total_questions_created integer DEFAULT 0,
  total_answers_submitted integer DEFAULT 0,
  total_volume_tokens bigint DEFAULT 0,
  total_protocol_fees bigint DEFAULT 0,
  total_creator_fees bigint DEFAULT 0,
  total_rewards_distributed bigint DEFAULT 0,
  unique_users integer DEFAULT 0
)
```

## Common Queries

### Get Question with Answers
```sql
SELECT q.*, array_agg(
  json_build_object(
    'content', a.content,
    'responder', a.responder,
    'score', a.score,
    'rank', a.rank
  ) ORDER BY a.answer_index
) as answers
FROM questions q
LEFT JOIN answers a ON q.question_id = a.question_id
WHERE q.question_id = $1
GROUP BY q.id;
```

### Get User Dashboard Data
```sql
SELECT 
  u.*,
  COUNT(DISTINCT q.question_id) as active_questions,
  COUNT(DISTINCT a.id) as pending_answers,
  COALESCE(SUM(rc.amount), 0) as unclaimed_rewards
FROM users u
LEFT JOIN questions q ON u.wallet = q.creator AND q.status = 'active'
LEFT JOIN answers a ON u.wallet = a.responder AND NOT a.rewarded
LEFT JOIN reward_claims rc ON u.wallet = rc.claimer
WHERE u.wallet = $1
GROUP BY u.wallet;
```

### Get Questions Ready for AI Evaluation
```sql
SELECT q.*
FROM questions q
LEFT JOIN evaluations e ON q.question_id = e.question_id
WHERE q.end_time < NOW()
  AND q.status = 'ended'
  AND e.id IS NULL
  AND q.total_submissions > 0;
```

### Check Emergency Refund Eligibility
```sql
SELECT q.question_id, a.responder, a.answer_index
FROM questions q
JOIN answers a ON q.question_id = a.question_id
LEFT JOIN evaluations e ON q.question_id = e.question_id
WHERE q.evaluation_deadline < NOW()
  AND e.id IS NULL
  AND NOT a.rewarded;
```

## Data Flow

### Question Lifecycle
1. **Creation** → Question created via factory contract
2. **Seeding** → Users fund question reward pool
3. **Submissions** → Users submit answers with fees
4. **AI Evaluation** → AI processes answers and generates rankings
5. **On-chain Evaluation** → Rankings submitted to contract
6. **Reward Distribution** → Winners claim their rewards

### Fee Distribution
For each answer submission:
- **Protocol Fee** (10%) → Treasury
- **Creator Fee** (10%) → Question creator
- **Reward Pool** (80%) → Available for winners

### Event Processing
Monitor these contract events:
- `QuestionCreated` → Insert into questions table
- `AnswerSubmitted` → Insert into answers table
- `Seeded` → Insert into seeds table
- `Evaluated` → Insert into evaluations table
- `RewardClaimed` → Insert into reward_claims table

## Indexes

Performance-critical indexes included:
- `questions(creator, status, end_time)`
- `answers(question_id, responder, score)`
- `contract_events(processed, block_number)`
- `reputation_history(wallet)`

## Automatic Time Calculation

The `end_time` and `evaluation_deadline` columns are automatically calculated using a database trigger:

```sql
-- Trigger function calculates times based on start_time and duration
CREATE OR REPLACE FUNCTION set_question_times()
RETURNS TRIGGER AS $$
BEGIN
  NEW.end_time = NEW.start_time + make_interval(secs => NEW.duration);
  NEW.evaluation_deadline = NEW.start_time + make_interval(secs => NEW.duration) + interval '7 days';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger runs before INSERT/UPDATE
CREATE TRIGGER set_question_times_trigger
  BEFORE INSERT OR UPDATE OF start_time, duration ON questions
  FOR EACH ROW EXECUTE FUNCTION set_question_times();
```

This automatically sets:
- `end_time` = `start_time` + `duration` seconds
- `evaluation_deadline` = `end_time` + 7 days (for emergency refunds)

## Views

### question_stats
Aggregated question data with evaluation status and emergency refund eligibility.

### user_stats  
User performance metrics including average scores and activity levels.