/*
 * Utility functions for QAR testing
 */

export function greet(name) {
    return `Hello, ${name}!`;
}

export function formatDate(date) {
    if (!date) {
        date = new Date();
    }
    return date.toISOString();
}

export const VERSION = "1.0.0";

