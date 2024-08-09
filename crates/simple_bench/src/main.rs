use reqwest::Client;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::task;

const URL: &str = "http://localhost:8000"; // Replace with your server's URL

#[tokio::main]
async fn main() {
    // Rebuild the host
    Command::new("roc")
        .arg("build.roc")
        .status()
        .expect("Failed to build the host");

    // Start the server
    let mut server_process = Command::new("roc")
        .arg("--optimize")
        .arg("examples/hello-web.roc")
        .spawn()
        .expect("Failed to start the server process");

    // Ensure the server has some time to start up
    tokio::time::sleep(Duration::from_secs(2)).await;

    let client = Client::new();
    let request_count = Arc::new(AtomicUsize::new(0));
    let success_count = Arc::new(AtomicUsize::new(0));

    let mut handles = vec![];

    for _ in 0..1000 {
        // Number of parallel requests
        let client = client.clone();
        let request_count = Arc::clone(&request_count);
        let success_count = Arc::clone(&success_count);

        let handle = task::spawn(async move {
            request_count.fetch_add(1, Ordering::SeqCst);

            let response = client.get(URL).send().await;
            if let Ok(resp) = response {
                if resp.status() == 200 {
                    success_count.fetch_add(1, Ordering::SeqCst);
                }
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.await.unwrap();
    }

    println!("Total requests: {}", request_count.load(Ordering::SeqCst));
    println!(
        "Successful responses: {}",
        success_count.load(Ordering::SeqCst)
    );

    // Stop the server after the test
    server_process
        .kill()
        .expect("Failed to kill the server process");
}
