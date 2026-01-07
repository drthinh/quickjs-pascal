// Stability Test Suite for QuickJS Pascal Integration
// Tests memory leaks, stress, error handling, and resource cleanup

console.log("=== QuickJS Pascal Stability Test Suite ===\n");

var testResults = {
    passed: 0,
    failed: 0,
    errors: []
};

function assert(condition, message) {
    if (condition) {
        testResults.passed++;
        console.log("✓ PASS: " + message);
    } else {
        testResults.failed++;
        var errorMsg = "✗ FAIL: " + message;
        testResults.errors.push(errorMsg);
        console.log(errorMsg);
    }
}

function testResult() {
    console.log("\n=== Test Results ===");
    console.log("Passed: " + testResults.passed);
    console.log("Failed: " + testResults.failed);
    console.log("Total: " + (testResults.passed + testResults.failed));
    
    if (testResults.errors.length > 0) {
        console.log("\nErrors:");
        testResults.errors.forEach(function(err) {
            console.log("  " + err);
        });
    }
    
    return testResults.failed === 0;
}

// ========== Test 1: Basic Functionality ==========
console.log("--- Test 1: Basic Functionality ---");
try {
    var x = 10;
    var y = 20;
    assert(x + y === 30, "Basic arithmetic");
    assert(typeof console !== "undefined", "Console object exists");
    assert(typeof console.log === "function", "Console.log is a function");
} catch (e) {
    assert(false, "Basic functionality test threw: " + e);
}

// ========== Test 2: Memory Stress Test ==========
console.log("\n--- Test 2: Memory Stress Test ---");
try {
    var iterations = 1000;
    var largeArray = [];
    
    for (var i = 0; i < iterations; i++) {
        largeArray.push({
            id: i,
            data: "This is a test string " + i,
            nested: {
                value: i * 2,
                array: new Array(100).fill(i)
            }
        });
    }
    
    assert(largeArray.length === iterations, "Large array created (" + iterations + " items)");
    
    // Test array operations
    var sum = 0;
    for (var i = 0; i < largeArray.length; i++) {
        sum += largeArray[i].id;
    }
    assert(sum === (iterations * (iterations - 1)) / 2, "Array iteration and calculation");
    
    // Clear array
    largeArray = null;
    assert(true, "Memory stress test completed");
} catch (e) {
    assert(false, "Memory stress test threw: " + e);
}

// ========== Test 3: String Operations Stress ==========
console.log("\n--- Test 3: String Operations Stress ---");
try {
    var str = "";
    var targetLength = 10000;
    
    for (var i = 0; i < targetLength; i++) {
        str += "A";
    }
    
    assert(str.length === targetLength, "String concatenation (" + targetLength + " chars)");
    
    // String operations
    var reversed = str.split("").reverse().join("");
    assert(reversed.length === targetLength, "String reverse operation");
    assert(reversed[0] === "A" && reversed[targetLength - 1] === "A", "String reverse correctness");
    
    assert(true, "String operations stress test completed");
} catch (e) {
    assert(false, "String operations stress test threw: " + e);
}

// ========== Test 4: Function Call Stress ==========
console.log("\n--- Test 4: Function Call Stress ---");
try {
    function factorial(n) {
        if (n <= 1) return 1;
        return n * factorial(n - 1);
    }
    
    var result = factorial(20);
    assert(result > 0, "Recursive function calls (factorial)");
    
    // Iterative function calls
    function add(a, b) { return a + b; }
    var sum = 0;
    for (var i = 0; i < 10000; i++) {
        sum = add(sum, i);
    }
    assert(sum === (10000 * 9999) / 2, "Iterative function calls (10000 iterations)");
    
    assert(true, "Function call stress test completed");
} catch (e) {
    assert(false, "Function call stress test threw: " + e);
}

// ========== Test 5: Error Handling ==========
console.log("\n--- Test 5: Error Handling ---");
try {
    // Test try-catch
    try {
        throw new Error("Test error");
        assert(false, "Should have thrown error");
    } catch (e) {
        assert(e.message === "Test error", "Error caught correctly");
    }
    
    // Test division by zero handling
    try {
        var result = 1 / 0;
        assert(result === Infinity || !isFinite(result), "Division by zero handled");
    } catch (e) {
        assert(false, "Division by zero should not throw: " + e);
    }
    
    // Test null/undefined access
    try {
        var obj = null;
        var x = obj.property;
        assert(false, "Should have thrown on null access");
    } catch (e) {
        assert(true, "Null access error caught");
    }
    
    assert(true, "Error handling test completed");
} catch (e) {
    assert(false, "Error handling test threw: " + e);
}

// ========== Test 6: Object Creation Stress ==========
console.log("\n--- Test 6: Object Creation Stress ---");
try {
    var objects = [];
    var count = 5000;
    
    for (var i = 0; i < count; i++) {
        objects.push({
            id: i,
            name: "Object" + i,
            value: Math.random(),
            timestamp: Date.now(),
            metadata: {
                created: i,
                modified: i + 1
            }
        });
    }
    
    assert(objects.length === count, "Object creation (" + count + " objects)");
    
    // Test object property access
    var found = 0;
    for (var i = 0; i < objects.length; i++) {
        if (objects[i].id === i && objects[i].name === "Object" + i) {
            found++;
        }
    }
    assert(found === count, "Object property access verification");
    
    objects = null;
    assert(true, "Object creation stress test completed");
} catch (e) {
    assert(false, "Object creation stress test threw: " + e);
}

// ========== Test 7: Array Operations Stress ==========
console.log("\n--- Test 7: Array Operations Stress ---");
try {
    var arr = [];
    var size = 5000;
    
    // Push operations
    for (var i = 0; i < size; i++) {
        arr.push(i);
    }
    assert(arr.length === size, "Array push operations");
    
    // Pop operations
    var popped = 0;
    while (arr.length > 0) {
        arr.pop();
        popped++;
    }
    assert(popped === size, "Array pop operations");
    assert(arr.length === 0, "Array is empty after pops");
    
    // Map operations
    arr = [];
    for (var i = 0; i < 1000; i++) {
        arr.push(i);
    }
    var mapped = arr.map(function(x) { return x * 2; });
    assert(mapped.length === 1000, "Array map operations");
    assert(mapped[500] === 1000, "Array map correctness");
    
    assert(true, "Array operations stress test completed");
} catch (e) {
    assert(false, "Array operations stress test threw: " + e);
}

// ========== Test 8: Closure and Scope ==========
console.log("\n--- Test 8: Closure and Scope ---");
try {
    function createCounter() {
        var count = 0;
        return function() {
            count++;
            return count;
        };
    }
    
    var counter1 = createCounter();
    var counter2 = createCounter();
    
    assert(counter1() === 1, "Closure counter 1 - first call");
    assert(counter1() === 2, "Closure counter 1 - second call");
    assert(counter2() === 1, "Closure counter 2 - independent");
    assert(counter1() === 3, "Closure counter 1 - third call");
    
    assert(true, "Closure and scope test completed");
} catch (e) {
    assert(false, "Closure and scope test threw: " + e);
}

// ========== Test 9: Long-Running Loop ==========
console.log("\n--- Test 9: Long-Running Loop ---");
try {
    var iterations = 100000;
    var sum = 0;
    
    for (var i = 0; i < iterations; i++) {
        sum += i;
    }
    
    var expected = (iterations * (iterations - 1)) / 2;
    assert(sum === expected, "Long-running loop (" + iterations + " iterations)");
    
    assert(true, "Long-running loop test completed");
} catch (e) {
    assert(false, "Long-running loop test threw: " + e);
}

// ========== Test 10: Nested Structures ==========
console.log("\n--- Test 10: Nested Structures ---");
try {
    var depth = 100;
    var obj = {};
    var current = obj;
    
    // Create deeply nested object
    for (var i = 0; i < depth; i++) {
        current.level = i;
        current.next = {};
        current = current.next;
    }
    
    // Traverse nested structure
    var levels = 0;
    current = obj;
    while (current && current.next) {
        levels++;
        current = current.next;
    }
    
    assert(levels === depth, "Deeply nested structure (" + depth + " levels)");
    
    assert(true, "Nested structures test completed");
} catch (e) {
    assert(false, "Nested structures test threw: " + e);
}

// ========== Test 11: Math Operations ==========
console.log("\n--- Test 11: Math Operations ---");
try {
    var mathTests = [
        Math.abs(-5) === 5,
        Math.max(1, 2, 3) === 3,
        Math.min(1, 2, 3) === 1,
        Math.floor(3.7) === 3,
        Math.ceil(3.2) === 4,
        Math.round(3.5) === 4,
        Math.sqrt(16) === 4,
        Math.pow(2, 8) === 256
    ];
    
    var allPassed = mathTests.every(function(test) { return test; });
    assert(allPassed, "Math operations");
    
    // Stress test math
    var sum = 0;
    for (var i = 0; i < 10000; i++) {
        sum += Math.sin(i) + Math.cos(i);
    }
    assert(isFinite(sum), "Math stress test (sin/cos)");
    
    assert(true, "Math operations test completed");
} catch (e) {
    assert(false, "Math operations test threw: " + e);
}

// ========== Test 12: Date Operations ==========
console.log("\n--- Test 12: Date Operations ---");
try {
    var now = new Date();
    var timestamp = now.getTime();
    
    assert(timestamp > 0, "Date creation and getTime()");
    assert(now instanceof Date, "Date instanceof check");
    
    // Date operations
    var future = new Date(timestamp + 86400000); // +1 day
    var diff = future.getTime() - now.getTime();
    assert(Math.abs(diff - 86400000) < 1000, "Date arithmetic");
    
    assert(true, "Date operations test completed");
} catch (e) {
    assert(false, "Date operations test threw: " + e);
}

// ========== Test 13: JSON Operations ==========
console.log("\n--- Test 13: JSON Operations ---");
try {
    var testObj = {
        name: "Test",
        value: 42,
        nested: {
            array: [1, 2, 3],
            bool: true
        }
    };
    
    var jsonStr = JSON.stringify(testObj);
    assert(typeof jsonStr === "string", "JSON.stringify");
    assert(jsonStr.length > 0, "JSON string not empty");
    
    var parsed = JSON.parse(jsonStr);
    assert(parsed.name === "Test", "JSON.parse correctness");
    assert(parsed.value === 42, "JSON.parse number");
    assert(parsed.nested.array.length === 3, "JSON.parse nested array");
    
    assert(true, "JSON operations test completed");
} catch (e) {
    assert(false, "JSON operations test threw: " + e);
}

// ========== Test 14: Regular Expressions ==========
console.log("\n--- Test 14: Regular Expressions ---");
try {
    var pattern = /^test\d+$/;
    assert(pattern.test("test123"), "Regex test - match");
    assert(!pattern.test("test"), "Regex test - no match");
    
    var str = "Hello World";
    var matches = str.match(/o/g);
    assert(matches && matches.length === 2, "Regex global match");
    
    var replaced = str.replace(/World/, "Universe");
    assert(replaced === "Hello Universe", "Regex replace");
    
    assert(true, "Regular expressions test completed");
} catch (e) {
    assert(false, "Regular expressions test threw: " + e);
}

// ========== Test 15: Prototype and Inheritance ==========
console.log("\n--- Test 15: Prototype and Inheritance ---");
try {
    function Parent(name) {
        this.name = name;
    }
    Parent.prototype.getName = function() {
        return this.name;
    };
    
    function Child(name, age) {
        Parent.call(this, name);
        this.age = age;
    }
    Child.prototype = Object.create(Parent.prototype);
    Child.prototype.constructor = Child;
    Child.prototype.getAge = function() {
        return this.age;
    };
    
    var child = new Child("Test", 10);
    assert(child.getName() === "Test", "Inheritance - parent method");
    assert(child.getAge() === 10, "Inheritance - child method");
    assert(child instanceof Child, "Inheritance - instanceof Child");
    assert(child instanceof Parent, "Inheritance - instanceof Parent");
    
    assert(true, "Prototype and inheritance test completed");
} catch (e) {
    assert(false, "Prototype and inheritance test threw: " + e);
}

// ========== Final Results ==========
console.log("\n");
var success = testResult();

if (success) {
    console.log("\n✓ All stability tests PASSED!");
    console.log("The QuickJS Pascal integration appears stable.");
} else {
    console.log("\n✗ Some stability tests FAILED!");
    console.log("Please review the errors above.");
}

// Return exit code (0 = success, 1 = failure)
// Note: QuickJS doesn't have process.exit, so we just log the result
// The test runner will check the console output to determine success/failure

