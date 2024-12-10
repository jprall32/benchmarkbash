# benchmarkbash
Product Requirements Document (PRD)
Title: Universal Benchmarking Script for Linux Systems
Version: 1.0
Author: Jon Prall/ChatGPT
Last Updated: 12/9/24

## Introduction
The Universal Benchmarking Script provides a highly portable, dependency-minimized solution for benchmarking CPU, RAM, storage, and GPU performance across a wide variety of Linux-based systems, including virtual machines, WSL 2 environments, and systems with diverse GPU configurations. The script outputs performance metrics in both human-readable and JSON formats.

## Goals and Objectives
Stress test and benchmark system components (CPU, RAM, storage, and GPU).
Provide meaningful and comparable performance metrics.
Handle a wide range of system configurations, including headless environments, virtual GPUs, and physical GPUs.
Maintain high portability with minimal dependencies.
Ensure concise yet detailed output for users and integration with monitoring systems.

## Features and Specifications
System Information Collection
Detect CPU architecture, core count, and model.
Detect GPU vendor, model, memory, and type.

## Output Formats
Human-readable summary.
Detailed JSON file (benchmark_results.json).

## Progress and Logging
Real-time status updates during benchmark execution.
Clear error handling with descriptive logs.

## CPU Benchmark
Methodology: Use bc to calculate Pi to a specified number of decimal places.
Stress Test: Fully utilizes all CPU cores/threads.
Performance Metric: Decimal places per second.
Benchmark Duration: Fixed time window (30 seconds).

## RAM Benchmark
Methodology: Measure memory throughput using dd to write to /dev/null.
Performance Metric: Throughput in GB/s.
Duration: Approximately 1 second, optimized for speed and meaningful results.

## Storage Benchmark
Methodology: Measure write speed using dd to write non-compressible data (/dev/urandom) to a temporary file.
Performance Metric: Write speed in MB/s or GB/s.
Configuration:
File size: 1 GB.
Direct I/O to bypass caching.
Cleanup: Deletes temporary test files after benchmarking.

## GPU Benchmark
Detection: Utilize lspci, glxinfo, and OpenCL tools to identify GPUs.
Detect and differentiate between physical, virtual, and integrated GPUs.

## Benchmarking Methods:
NVIDIA GPUs: Use CUDA's matrixMul example for FLOPS measurement.
OpenGL GPUs: Use glmark2 with a shading test for FPS measurement.
Fallback: Use glxgears as a last resort for unsupported configurations.

## Performance Metric:
NVIDIA GPUs: GFlops (calculated over a 1-second duration).
OpenGL GPUs: Frames per second (FPS).
Fallback: FPS from glxgears.
Headless Support: Use off-screen rendering for GPU benchmarks when no display is available.

## Implementation Details
Dependencies: Core utilities: bash, jq, dd, bc.
Optional dependencies (for GPU benchmarks): NVIDIA CUDA toolkit (for NVIDIA GPUs). glmark2 for OpenGL tests. glxinfo for GPU detection.

## Script Behavior
Collect system information.
Sequentially execute benchmarks: CPU, RAM, Storage, and GPU (with fallback options).
Compile results into a JSON file and display a summary.
Handle errors gracefully and log failures for debugging.

## Error Handling
Detection Failures: Log missing tools or unavailable hardware.
Benchmark Failures: Provide descriptive messages for debugging.
Dependencies: Skip unavailable tests with clear error reporting.
Limitations
GPU benchmarking may vary significantly based on driver availability and compatibility.
RAM and storage tests may be influenced by system cache and write optimizations.

## Acceptance Criteria
Script executes successfully on both physical and virtual machines.
All supported benchmarks complete with accurate results.
JSON output conforms to the specified schema.
Clear and concise summary output is presented to the user.
Display a concise summary in human-readable format.
Error Handling:

Skip unavailable tests with descriptive logs.
Ensure dependencies are minimal and clearly identified.
Other Requirements:

Include real-time status updates.
Minimize dependencies, prioritize portability.
Provide meaningful, comparable metrics across systems.
Clean up temporary files after execution.

## The prompt:

Write a highly portable Bash script for benchmarking system performance, including CPU, RAM, storage, and GPU. The script should:

Detect System Information:

Retrieve CPU architecture, core count, model.
Detect GPU model, vendor, and memory size.
Benchmarks:

CPU Benchmark: Calculate Pi using bc for 30 seconds, measure decimal places per second.
RAM Benchmark: Use dd to measure memory throughput with a target duration of ~1 second.
Storage Benchmark: Use dd with /dev/urandom to measure direct write speed (1 GB file).
GPU Benchmark: Include:
For NVIDIA GPUs, use the CUDA matrixMul example to measure FLOPS.
For OpenGL GPUs, use glmark2 with the shading test for FPS measurement.
For unsupported configurations, fallback to glxgears.
Support off-screen rendering for headless systems.
Output:

Generate a detailed JSON file with benchmark results.
Display a concise summary in human-readable format.
Error Handling:

Skip unavailable tests with descriptive logs.
Ensure dependencies are minimal and clearly identified.
Other Requirements:

Include real-time status updates.
Minimize dependencies, prioritize portability.
Provide meaningful, comparable metrics across systems.
Clean up temporary files after execution.
The script should handle diverse configurations, including virtual GPUs, WSL 2, and physical GPUs. Ensure the implementation is robust and user-friendly.
