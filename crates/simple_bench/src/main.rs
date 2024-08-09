use reqwest::Client;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::task;

const PORT: &str = "8001";
const URL: &str = "http://localhost:8001";
const NUM_REQUESTS: usize = 25;
const ROC_TEST_EXAMPLE: &str = "examples/hello-web.roc";
const DELAY_WAIT_SERVER_STARTUP: u64 = 2;
const EXPECTED_HTTP_OK_STATUS: u16 = 200;

#[tokio::main]
async fn main() {
    // Rebuild the host
    Command::new("roc")
        .arg("build.roc")
        .status()
        .expect("Failed to build the host");

    // Start the server
    let mut server_process = {
        Command::new("roc")
            // .arg("--optimize")
            .arg("--profiling")
            .arg(ROC_TEST_EXAMPLE)
            .env("ROC_BASIC_WEBSERVER_PORT", PORT)
            .spawn()
            .expect("Failed to start the server process")
    };

    // Ensure the server has some time to start up
    tokio::time::sleep(Duration::from_secs(DELAY_WAIT_SERVER_STARTUP)).await;

    let client = Client::new();
    let request_count = Arc::new(AtomicUsize::new(0));
    let success_count = Arc::new(AtomicUsize::new(0));

    let mut handles = vec![];

    for _ in 0..NUM_REQUESTS {
        // Number of parallel requests
        let client = client.clone();
        let request_count = Arc::clone(&request_count);
        let success_count = Arc::clone(&success_count);

        let handle = task::spawn(async move {
            request_count.fetch_add(1, Ordering::SeqCst);

            let response = client.get(URL).send().await;
            if let Ok(resp) = response {
                if resp.status() == EXPECTED_HTTP_OK_STATUS {
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
