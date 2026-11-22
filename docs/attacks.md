# Attack Log: Round 1

On Nov 22, 2026 I ran four AWS attack techniques against my lab using [Stratus Red Team](https://github.com/DataDog/stratus-red-team), then went into Elastic to see if I could find each one in the CloudTrail logs. I could. This is what I ran, what it looked like, and what I learned.

One thing to keep in mind: every attack ran as my `sam-admin` user from my own IP. That's on purpose. In a lot of real cloud breaches the attacker is using a stolen key that belongs to a real person, so the logs just show a normal user doing things. You can't catch them by who they are, only by what they do.

## The four attacks

| # | What I ran | MITRE ATT&CK | What showed up in CloudTrail | Time (ET) |
|---|---|---|---|---|
| 1 | Stopped a CloudTrail trail (`cloudtrail-stop`) | [T1562.008](https://attack.mitre.org/techniques/T1562/008/) | `StopLogging` | 10:36 |
| 2 | Created a new admin user (`iam-create-admin-user`) | [T1136.003](https://attack.mitre.org/techniques/T1136/003/) | `CreateUser`, `AttachUserPolicy`, `CreateAccessKey` | 10:47 |
| 3 | Added a backdoor key to an existing user (`iam-backdoor-user`) | [T1098.001](https://attack.mitre.org/techniques/T1098/001/) | `CreateAccessKey` | 10:48 |
| 4 | Opened an S3 bucket to an outside account (`s3-backdoor-bucket-policy`) | [T1537](https://attack.mitre.org/techniques/T1537/) | `PutBucketPolicy` | 10:49 |

All four were caught by my trail (`cdl-trail`) and showed up in Elastic.

## What it looked like in Elastic

This is the query I used to pull everything into one timeline:

```
FROM logs-aws.cloudtrail-default
| WHERE event.action IN ("StopLogging", "CreateUser", "AttachUserPolicy",
                         "CreateAccessKey", "PutBucketPolicy")
| KEEP @timestamp, event.action, user.name, source.ip, user_agent.original, event.outcome
| SORT @timestamp ASC
```

It returned 9 events:

| Time | Event | What it actually was |
|---|---|---|
| 10:36:36 | `PutBucketPolicy` | Stratus setting up a bucket for its test trail (not an attack) |
| 10:36:39 | `StopLogging` | Attack 1 |
| 10:47:33 | `CreateUser` | Attack 2 |
| 10:47:33 | `AttachUserPolicy` | Attack 2 |
| 10:47:33 | `CreateAccessKey` | Attack 2 |
| 10:48:50 | `CreateUser` | Stratus creating the "legit" user it was about to backdoor (not an attack) |
| 10:48:52 | `CreateAccessKey` | Attack 3 |
| 10:49:35 | `PutBucketPolicy` | Attack 4 |

## Notes on each one

**1. Stopping CloudTrail.** This is an attacker trying to turn off the cameras before doing anything else. Stratus made its own test trail and stopped that one, so my real trail kept recording and caught the `StopLogging` call. There's almost never a good reason to stop a trail, so this one should always be a high-priority alert.

**2. Creating an admin user.** This was the easiest one to spot. The user was created, given AdministratorAccess, and handed an access key all in the same second. Nobody does that by hand that fast, so it's clearly a script. It's also persistence: even if the original stolen key gets cancelled, the attacker still has their own admin account.

**3. Backdooring an existing user.** Sneakier than #2. No new user shows up anywhere, an existing user just quietly gets a second access key that the attacker keeps. The giveaway is that the person creating the key (`sam-admin`) isn't the person the key belongs to.

**4. Backdooring the bucket policy.** This one surprised me. The attacker edits the bucket's policy to let an outside AWS account (`193672423079`) read everything. My bucket has the S3 public access block turned on, but that doesn't stop this, because giving access to one specific account doesn't count as "public." The attacker doesn't even need to steal anything right away. They just leave themselves a door to come back through later.

## What I learned

- **Not every match is an attack.** Two of the nine events were just Stratus setting things up, and they look exactly like the real attacks. If I wrote a rule that alerts on every `PutBucketPolicy`, I'd get a lot of false alarms. The rules I write next need to be more specific, like only alerting when a bucket policy mentions an account that isn't mine.
- **Speed and order matter.** The admin user attack stood out because of how fast and in what order things happened, not because of any single event.
- **The user agent is worth checking.** It shows what tool made the request, which can help tell an attack tool or script apart from normal CLI use.

## Issues I ran into

- **No GuardDuty.** I planned to compare my detections against GuardDuty, but the AWS Free plan blocks it with a Service Control Policy set by the parent organization. Even my admin user gets an explicit deny. So all the detection in this lab is my own rules in Elastic.
- **One cleanup got blocked.** After attack 3, Stratus couldn't delete its test user because the same SCP blocks deleting login profiles. The backdoor key itself was removed, and the leftover user has no keys and no permissions, so it can't do anything.
- **First run failed.** The first time I ran the CloudTrail attack it errored with "Trail name cannot be blank" because the setup step didn't finish. Running `stratus cleanup` and trying again fixed it.

## Next

Four more attacks, then turning all eight into detection rules in Elastic so they alert automatically instead of me having to go looking.
