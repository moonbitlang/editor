///|
/// Runtime-neutral policy for starting a closed set of async tasks. Lower
/// packages default to this ordered runner; hosts with their own async runtime
/// may inject a concurrent runner without coupling shared packages to that
/// runtime.
pub async fn run_async_tasks_sequentially(
  tasks : Array[async () -> Unit],
) -> Unit {
  for task in tasks {
    task()
  }
}
