// Example: Sử dụng SQLite qua QuickJS API
// 
// LƯU Ý: File này chỉ là ví dụ. Để chạy được, cần:
// 1. Implement RegisterSqliteModule trong main.pas
// 2. Link với sqlite3 library
// 3. Gọi RegisterSqliteModule(ctx) sau khi tạo context

console.log("=== SQLite Integration Example ===");

if (typeof sqlite === "undefined") {
  console.log("SQLite module not available");
  console.log("Make sure RegisterSqliteModule() is called in Pascal code");
} else {
  console.log("SQLite module is available!");
  
  try {
    // 1. Mở database
    console.log("\n1. Opening database...");
    var db = sqlite.open("test.db");
    console.log("   Database opened successfully");
    
    // 2. Tạo bảng
    console.log("\n2. Creating table...");
    db.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)");
    console.log("   Table created");
    
    // 3. Insert dữ liệu
    console.log("\n3. Inserting data...");
    db.exec("INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')");
    db.exec("INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')");
    console.log("   Data inserted");
    
    // 4. Query với prepare/step
    console.log("\n4. Querying data with prepare/step...");
    var stmt = db.prepare("SELECT id, name, email FROM users");
    
    var rowCount = 0;
    while (stmt.step()) {
      rowCount++;
      var colCount = stmt.getColumnCount();
      console.log("   Row " + rowCount + ":");
      
      for (var i = 0; i < colCount; i++) {
        var colName = stmt.getColumnName(i);
        var colValue = stmt.getColumn(i);
        console.log("     " + colName + ": " + colValue);
      }
    }
    
    console.log("   Total rows: " + rowCount);
    
    // 5. Query đơn giản với exec (nếu hỗ trợ callback)
    console.log("\n5. Simple query with exec...");
    // db.exec("SELECT * FROM users", function(row) { ... }); // Nếu implement callback
    
    console.log("\n=== SQLite Test Completed ===");
    
    // Database sẽ tự động đóng khi object bị GC
    // Hoặc có thể thêm db.close() nếu implement
    
  } catch (e) {
    console.log("Error:", e);
  }
}

