// ucode -L forkop/files/usr/lib tests/subscription_source_entry.uc
let parser = require("subscription.parser");

function expect(ok, message) {
    if (!ok)
        die(message + "\n");
}

for (let url in [
    "https://feed.example/subscription/token?format=xray",
    "https://another-provider.example:8443/subscription",
    "https://192.0.2.1/subscription",
    "https://[2001:db8::1]/subscription",
    "https://aes2215.vs2112.51343.ru/subscription",
    "https://sub.flintnet.pro/subscription",
    "https://sub.hat.onl/subscription"
]) {
    let result = parser.parse_subscription_source_entry(url);
    expect(result.valid, "HTTPS provider rejected: " + url);
    expect(result.url == url, "Subscription URL was changed");
    expect(result.user_agent == "", "Parser should preserve configured User-Agent handling");
}

for (let url in [
    "", "http://feed.example/subscription", "file:///tmp/subscription",
    "https:///subscription", "https://", "https://feed.example/a b",
    "https://feed.example/\ninjected", "https://feed.example/subscription | Custom/1"
])
    expect(!parser.parse_subscription_source_entry(url).valid, "Invalid source accepted: " + url);

let trimmed = parser.parse_subscription_source_entry("  https://feed.example/subscription\n");
expect(trimmed.valid && trimmed.url == "https://feed.example/subscription", "Outer whitespace was not trimmed");
print("Subscription sources: arbitrary HTTPS providers, existing providers, URL validation and User-Agent handling passed\n");
