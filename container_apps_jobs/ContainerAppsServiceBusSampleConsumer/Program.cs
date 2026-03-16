using Azure.Messaging.ServiceBus;

string connectionString = Environment.GetEnvironmentVariable("serviceBusConnectionString")
    ?? throw new ArgumentNullException("serviceBusConnectionString");
string queueName = Environment.GetEnvironmentVariable("serviceBusQueue")
    ?? throw new ArgumentNullException("serviceBusQueue");
int maxMessagesPerRun = int.TryParse(Environment.GetEnvironmentVariable("MAX_MESSAGES_PER_RUN"), out int parsedMaxMessages)
    ? parsedMaxMessages
    : 20;
int maxIdleWaitSeconds = int.TryParse(Environment.GetEnvironmentVariable("MAX_IDLE_WAIT_SECONDS"), out int parsedIdleSeconds)
    ? parsedIdleSeconds
    : 15;

if (maxMessagesPerRun <= 0)
{
    throw new ArgumentOutOfRangeException("MAX_MESSAGES_PER_RUN", "Value must be greater than 0.");
}

if (maxIdleWaitSeconds <= 0)
{
    throw new ArgumentOutOfRangeException("MAX_IDLE_WAIT_SECONDS", "Value must be greater than 0.");
}

await using var client = new ServiceBusClient(connectionString);
await using var receiver = client.CreateReceiver(queueName);

Console.WriteLine($"Starting batch receive. Queue={queueName}, MaxMessages={maxMessagesPerRun}, IdleWaitSeconds={maxIdleWaitSeconds}");

int processedCount = 0;
while (processedCount < maxMessagesPerRun)
{
    var message = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(maxIdleWaitSeconds));
    if (message is null)
    {
        Console.WriteLine("No message available within idle wait window.");
        break;
    }

    string body = message.Body.ToString();
    await Task.Delay(150); // simulate work
    Console.WriteLine(body);

    await receiver.CompleteMessageAsync(message);
    processedCount++;
}

Console.WriteLine($"Processed {processedCount} message(s). Exiting.");
