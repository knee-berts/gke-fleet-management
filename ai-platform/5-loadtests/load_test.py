import time
import json
import urllib.request
import argparse
import sys
import statistics
import concurrent.futures

def chat_completion(url, model, prompt, request_id):
    data = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.0,
        "max_tokens": 50, # Keep short for speed
        "stream": False 
    }
    
    start_time = time.time()
    try:
        req = urllib.request.Request(
            f"{url}/v1/chat/completions", 
            data=json.dumps(data).encode('utf-8'), 
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            body = response.read()
            # response_data = json.loads(body) # optimizing: don't parse unless needed
            pass
            
    except Exception as e:
        # print(f"[{request_id}] Error: {e}") # Reduce spam
        return 0, False

    end_time = time.time()
    total_latency_ms = (end_time - start_time) * 1000
    return total_latency_ms, True

def run_load_test(url, model, duration, concurrency):
    print(f"Starting load test: {duration}s duration, {concurrency} threads...")
    latencies = []
    success_count = 0
    error_count = 0
    
    start_time = time.time()
    end_time = start_time + duration
    
    # Prompt
    prompt = "Explain the history of Rome briefly."

    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = []
        
        while time.time() < end_time:
            # Fill pool
            while len(futures) < concurrency and time.time() < end_time:
                req_id = f"req-{len(futures)}"
                futures.append(executor.submit(chat_completion, url, model, prompt, req_id))
            
            # Wait for at least one to finish? 
            # Actually simpler approach: submit batch, wait, repeat? 
            # Or continuous. Continuous is better for RPS.
            
            # For simplicity in this script without async:
            # We will just submit a batch, wait for all, repeat.
            # This counts as "iterations".
            
            batch_futures = [executor.submit(chat_completion, url, model, prompt, f"req-{i}") for i in range(concurrency)]
            for f in concurrent.futures.as_completed(batch_futures):
                lat, success = f.result()
                if success:
                    latencies.append(lat)
                    success_count += 1
                else:
                    error_count += 1
            
            if time.time() >= end_time:
                break

    total_time = time.time() - start_time
    
    # Report
    print(f"\n{'='*40}")
    print(f"LOAD TEST REPORT")
    print(f"{'='*40}")
    print(f"Total Requests: {success_count + error_count}")
    print(f"Successful:     {success_count}")
    print(f"Errors:         {error_count}")
    print(f"Duration:       {total_time:.2f} s")
    print(f"RPS:            {success_count / total_time:.2f}")
    
    if latencies:
        latencies.sort()
        p50 = statistics.median(latencies)
        p90 = latencies[int(len(latencies) * 0.9)]
        p99 = latencies[int(len(latencies) * 0.99)]
        avg = statistics.mean(latencies)
        
        print(f"\nLatency Distribution (ms):")
        print(f"  Avg: {avg:.2f}")
        print(f"  P50: {p50:.2f}")
        print(f"  P90: {p90:.2f}")
        print(f"  P99: {p99:.2f}")
        print(f"  Min: {latencies[0]:.2f}")
        print(f"  Max: {latencies[-1]:.2f}")
    else:
        print("\nNo successful requests to calculate latency.")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True, help="Gateway URL")
    parser.add_argument("--model", required=True, help="Model ID")
    parser.add_argument("--region", required=True, help="Region")
    parser.add_argument("--duration", type=int, default=10, help="Duration in seconds")
    parser.add_argument("--concurrency", type=int, default=2, help="Concurrency")
    args = parser.parse_args()

    print(f"--- Client Region: {args.region} ---")
    print(f"Target: {args.url}")
    print(f"Model: {args.model}")

    # Functional Checks first
    print(f"\n[Phase 1] Warmup & Functional Check")
    lat, success = chat_completion(args.url, args.model, "Warmup", "warmup")
    if success:
        print(f"✓ Warmup successful ({lat:.2f} ms)")
    else:
        print(f"✗ Warmup failed. Aborting load test.")
        # Re-run to see error
        try:
            req = urllib.request.Request(
                f"{args.url}/v1/chat/completions", 
                data=json.dumps({"model": args.model, "messages": [{"role": "user", "content": "test"}]}).encode('utf-8'), 
                headers={'Content-Type': 'application/json'}
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                print(f"DEBUG: Response status: {response.status}")
                print(f"DEBUG: Response body: {response.read()}")
        except Exception as e:
            print(f"DEBUG: Connection Error: {e}")
            if hasattr(e, 'read'):
                print(f"DEBUG: Error Body: {e.read()}")
            
        sys.exit(1)

    # Load Test
    print(f"\n[Phase 2] Load Test")
    run_load_test(args.url, args.model, args.duration, args.concurrency)

if __name__ == "__main__":
    main()
