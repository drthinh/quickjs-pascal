// 1. A function that returns a Promise (simulates an async operation)
function resolveAfter2Seconds() {
  return new Promise(resolve => {
    setTimeout(() => {
      resolve('Operation completed');
    }, 2000); // Resolves with a value after 2 seconds
  });
}

// 2. An async function to use 'await'
async function f1() {
  console.log('Starting...');

  // The 'await' keyword pauses the function execution until the Promise resolves
  const result = await resolveAfter2Seconds();

  // This line runs only after the Promise has settled
  console.log(result); // Output: Operation completed
  console.log('Finished.');
}

// 3. Call the async function
f1();

// This code runs immediately without waiting for f1() to finish its internal async operation
console.log('The rest of the script continues to run in the meantime.');
