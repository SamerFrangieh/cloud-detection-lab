# Attack Log
 
I ran eight AWS attack techniques against my lab with [Stratus Red Team](https://github.com/DataDog/stratus-red-team), found each one in the CloudTrail logs in Elastic, and then wrote detection rules so they alert on their own instead of me having to go looking. This is what I ran, what it looked like, and how the rules did.
 
Every attack ran as my `sam-admin` user from my own IP. That's on purpose. In a lot of real cloud breaches the attacker is using a stolen key that belongs to a real person, so the logs just show a normal user doing things. You can't catch them by who they are, only by what they do.
 
## The attacks
 
| # | What I ran | MITRE ATT&CK | What showed up in CloudTrail | Rule that caught it |
|---|---|---|---|---|
| 1 | Stopped a CloudTrail trail (`cloudtrail-stop`) | [T1685.002](https://attack.mitre.org/techniques/T1685/002/) Disable or Modify Cloud Log | `StopLogging` | CloudTrail Tampering ✅ |
| 2 | Created a new admin user (`iam-create-admin-user`) | [T1136.003](https://attack.mitre.org/techniques/T1136/003/) Create Cloud Account | `CreateUser`, `AttachUserPolicy`, `CreateAccessKey` | Admin Policy Attached ✅ + Access Key for Another User ✅ |
| 3 | Added a backdoor key to an existing user (`iam-backdoor-user`) | [T1098.001](https://attack.mitre.org/techniques/T1098/001/) Additional Cloud Credentials | `CreateAccessKey` | Access Key for Another User ✅ |
| 4 | Opened an S3 bucket to an outside account (`s3-backdoor-bucket-policy`) | [T1537](https://attack.mitre.org/techniques/T1537/) Transfer Data to Cloud Account | `PutBucketPolicy` | S3 Policy Grants External Account ✅ |
| 5 | Deleted a CloudTrail trail (`cloudtrail-delete`) | [T1685.002](https://attack.mitre.org/techniques/T1685/002/) Disable or Modify Cloud Log | `DeleteTrail` | CloudTrail Tampering ✅ |
| 6 | Stole EC2 instance credentials (`ec2-steal-instance-credentials`) | [T1552.005](https://attack.mitre.org/techniques/T1552/005/) Cloud Instance Metadata API | `SendCommand`, then API calls from the instance role outside AWS | SSM Command Sent ✅ |
| 7 | Tried to pull EC2 Windows passwords (`ec2-get-password-data`) | [T1552](https://attack.mitre.org/techniques/T1552/) Unsecured Credentials | `GetPasswordData` ×30 | EC2 Password Retrieved ✅ (30 alerts, since tuned) |
| 8 | Ran recon commands from an instance (`ec2-enumerate-from-instance`) | [T1580](https://attack.mitre.org/techniques/T1580/) Cloud Infrastructure Discovery | `SendCommand`, then `ListUsers`, `ListRoles`, `DescribeTrails`, etc. | SSM Command Sent ✅ (Discovery Burst retuned, see below) |
 
**Result: all 8 attacks were detected.** Attacks 1–4 were first run on Day 5 for manual hunting, then run again on Day 6 after the rules existed.
 
A note on the MITRE IDs: I originally mapped the CloudTrail attacks to T1562.008 (Impair Defenses). When I went to tag the rules in Elastic, it was using a newer version of ATT&CK (v20), where Defense Evasion was split into **Stealth** and **Defense Impairment**, and log tampering moved to **T1685.002**. I updated everything to the current IDs.
 
## The detection rules
 
All rules are ES|QL rules in Elastic Security. They run every 5 minutes with 20 extra minutes of look-back, because CloudTrail delivers logs 5–15 minutes late. Without the look-back the rule would check a window the logs haven't reached yet.
 
| Rule | Logic | Severity |
|---|---|---|
| CloudTrail Tampering | `StopLogging`, `DeleteTrail` or `UpdateTrail` | High |
| Admin Policy Attached to IAM User | `AttachUserPolicy` where the policy is `AdministratorAccess` | High |
| Access Key Created for Another User | `CreateAccessKey` where the key's owner isn't the person creating it | Medium |
| S3 Bucket Policy Grants External Account | `PutBucketPolicy` naming an AWS account that isn't mine | High |
| EC2 Windows Password Retrieved | `GetPasswordData` (grouped per user and IP) | Medium |
| SSM Command Sent to Instance | `SendCommand` | Medium |
| Discovery Burst from Assumed Role | One role making 6+ different Describe/List/Get calls in the window | Low |
 
The rules fall into two styles:
- **"This should basically never happen"** (CloudTrail tampering, password retrieval, SSM commands). In my environment, any occurrence is suspicious.
- **"This happens normally, but not like this"** (admin policy, keys for other users, bucket policies). These need an extra condition to filter out normal activity, otherwise they'd fire all the time.
## Tuning I had to do
 
This was honestly the most useful part.
 
**False positive from Stratus's setup steps.** On Day 5 I noticed that Stratus's warmup also does a `PutBucketPolicy` that looks exactly like attack 4. If my rule alerted on every bucket policy change, I'd get false alarms. So the S3 rule only fires when the policy names an AWS account that isn't mine. On Day 6 the warmup did not trigger it, and the real attack did.
 
**30 alerts for one attack.** The password rule originally made one alert per event, and attack 7 calls `GetPasswordData` on 30 instance IDs, so one attack produced 30 alerts. In a real SOC that's alert fatigue, and it's how real attacks get ignored. I changed the rule to group the events (`STATS ... BY user.name, source.ip`) so one burst becomes one alert.
 
**Recon rule missed the recon.** My discovery rule needed 10 different Describe/List calls. When I read what attack 8 actually ran, only 6 of its calls matched, because real recon also uses a lot of `Get*` calls (`GetCallerIdentity`, `GetAccountSummary`, `GetAccountAuthorizationDetails`). I added `Get*` and lowered the threshold to 6. Interestingly, attack 8 was still caught anyway, by the SSM rule, because running commands on an instance requires `SendCommand`. Having more than one rule cover the same attack is what defense in depth looks like.
 
## Things I noticed along the way
 
- **Attack 6 is basically the Capital One breach.** Stratus ran `curl 169.254.169.254/latest/meta-data/iam/security-credentials/...` on the instance to grab its role credentials, then used them from my laptop. IMDSv2 (which I turned on for my own server) blocks the SSRF version of this from outside, but not someone who can already run commands on the box.
- **Attack 2 was the easiest to spot by eye.** A user created, made admin and given a key all in the same second. No human does that by hand.
- **The S3 public access block doesn't stop attack 4.** Granting access to one named outside account doesn't count as "public."
## Issues I ran into
 
- **No GuardDuty.** The AWS Free plan blocks it with a Service Control Policy set by the parent organization (`CreateDetector` explicit deny), so all detection in this lab is my own rules in Elastic.
- **One cleanup got blocked.** After attack 3, Stratus couldn't delete its test user because the same SCP blocks `iam:DeleteLoginProfile`. The backdoor key was removed, and the leftover user has no keys and no permissions.
- **First run failed.** The first CloudTrail attack errored with "Trail name cannot be blank" because the setup step didn't finish. Running `stratus cleanup` and trying again fixed it.
 
