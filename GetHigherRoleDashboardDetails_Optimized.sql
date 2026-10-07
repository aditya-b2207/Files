/*
 Performance-oriented rewrite for CompanyCode 1054 dashboard.
 Preserves 6 result sets and existing calendar-year YTD, monthly sales,
 order-status and turnover calculation definitions.
 Test output against old SP before production deployment.
*/
CREATE OR ALTER PROCEDURE dbo.GetHigherRoleDashboardDetails
    @UserCode NVARCHAR(50),
    @SelectedCustomer NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CONVERT(DATE, GETDATE());
    DECLARE @YearStart DATE = DATEFROMPARTS(YEAR(@Today), 1, 1);
    DECLARE @NextYearStart DATE = DATEADD(YEAR, 1, @YearStart);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);
    DECLARE @NextMonthStart DATE = DATEADD(MONTH, 1, @MonthStart);

    SET @SelectedCustomer = NULLIF(LTRIM(RTRIM(@SelectedCustomer)), N'');

    -- INSERT EXEC requires an ordinary matching target table, not a nested INSERT EXEC.
    CREATE TABLE #HierarchyRaw
    (
        CustomerCode NVARCHAR(50) NULL,
        CustomerName NVARCHAR(100) NULL
    );

    INSERT INTO #HierarchyRaw (CustomerCode, CustomerName)
    EXEC dbo.GetUserCustomers @UserCode = @UserCode;

    SELECT DISTINCT CustomerCode
    INTO #Customers
    FROM #HierarchyRaw
    WHERE CustomerCode IS NOT NULL
      AND (@SelectedCustomer IS NULL OR CustomerCode = @SelectedCustomer);

    CREATE UNIQUE CLUSTERED INDEX IX_Customers_Code ON #Customers(CustomerCode);
    DROP TABLE #HierarchyRaw;

    -- Materialize the eligible orders once. Keep one row per original OrdersMHZPC row.
    SELECT o.OrderNumber, o.OrderStatus, o.CustomerCode
    INTO #Orders
    FROM dbo.OrdersMHZPC AS o
    INNER JOIN #Customers AS c ON c.CustomerCode = o.CustomerCode;

    CREATE INDEX IX_Orders_OrderNumber ON #Orders(OrderNumber);

    -- Materialize distinct eligible invoice headers once. EXISTS avoids row
    -- multiplication when orders/dealer orders have multiple matching rows.
    -- DISTINCT matches original value-side invoice de-duplication semantics.
    SELECT DISTINCT
        h.BillingDocument,
        h.BillingDate,
        h.TotalInvoiceValue
    INTO #Invoices
    FROM dbo.TB_InvoiceHeader AS h
    WHERE h.SalesOrganisation = 'MZ01'
      AND EXISTS
      (
          SELECT 1
          FROM dbo.DealerOrderMHZPC AS d
          INNER JOIN #Orders AS o ON o.OrderNumber = d.OrderNumber
          WHERE d.SoNumber = h.SalesOrderNo
      );

    CREATE INDEX IX_Invoices_Document ON #Invoices(BillingDocument);

    -- 1. YTD and current-month sales: same two columns, same result-set position.
    SELECT
        ISNULL(SUM(CASE WHEN BillingDate >= @YearStart
                            AND BillingDate < @NextYearStart
                        THEN CONVERT(DECIMAL(18,2), TotalInvoiceValue)
                        ELSE 0 END), 0) AS TotalYTDSaleValue,
        ISNULL(SUM(CASE WHEN BillingDate >= @MonthStart
                            AND BillingDate < @NextMonthStart
                        THEN CONVERT(DECIMAL(18,2), TotalInvoiceValue)
                        ELSE 0 END), 0) AS TotalCurrentMonthSaleValue
    FROM #Invoices;

    -- 2 and 3. Pending and approved: one read, two result sets.
    DECLARE @PendingOrders INT, @ApprovedOrders INT;
    SELECT
        @PendingOrders = COUNT(CASE WHEN OrderStatus = 'Pending' THEN OrderNumber END),
        @ApprovedOrders = COUNT(CASE WHEN OrderStatus = 'Approved' THEN OrderNumber END)
    FROM #Orders;

    SELECT @PendingOrders AS PendingOrders;
    SELECT @ApprovedOrders AS ApprovedOrders;

    -- 4. Aging: separate ISNULL for each bucket avoids NULL propagation.
    SELECT
        SUM(ISNULL([0_30_Days],0) + ISNULL([31_60_Days],0) + ISNULL([61_90_Days],0)) AS [0_90_Days],
        SUM([91_120_Days]) AS [91_120_Days],
        SUM(ISNULL([121_150_Days],0) + ISNULL([151_180_Days],0)) AS [121_180_Days],
        SUM(ISNULL([181_210_Days],0) + ISNULL([210_365_Days],0)) AS [181_365_Days],
        SUM([Over_365_Days]) AS [Over_365_Days]
    FROM dbo.TB_CustomerAgeingReport AS a
    INNER JOIN #Customers AS c ON c.CustomerCode = a.CustomerCode
    WHERE a.CompanyCode = '1054';

    -- 5. Account summary: use order rows just as original INNER JOIN did;
    -- preserve each numeric conversion and zero default.
    SELECT
        ISNULL(SUM(d.BookingAmount),0) + ISNULL(SUM(d.SecondaryBookingAmount),0) AS TotalBookingAdvance,
        ISNULL(SUM(d.BalanceAmountToPay),0) + ISNULL(SUM(d.SecondaryBalanceAmountToPay),0) AS TotalBalanceDue,
        ISNULL(SUM(CONVERT(DECIMAL(18,2),d.OrderAmount)),0)
          + ISNULL(SUM(CONVERT(DECIMAL(18,2),d.SecondaryOrderAmount)),0) AS TotalOrderAmount
    FROM dbo.DealerOrderMHZPC AS d
    INNER JOIN #Orders AS o ON o.OrderNumber = d.OrderNumber;

    -- 6. Turnover by financial year. Value counts each distinct invoice
    -- document/date/value row; item quantities count each document/date once.
    -- These are distinct on purpose to replicate the original SP.
    ;WITH InvoiceValues AS
    (
        SELECT
            CASE WHEN MONTH(BillingDate) >= 4
                 THEN YEAR(BillingDate)
                 ELSE YEAR(BillingDate) - 1 END AS FYStart,
            SUM(CONVERT(DECIMAL(18,2), TotalInvoiceValue)) AS TotalValue
        FROM #Invoices
        GROUP BY CASE WHEN MONTH(BillingDate) >= 4
                      THEN YEAR(BillingDate)
                      ELSE YEAR(BillingDate) - 1 END
    ),
    InvoiceDates AS
    (
        SELECT DISTINCT BillingDocument, BillingDate
        FROM #Invoices
    ),
    InvoiceQuantities AS
    (
        SELECT
            CASE WHEN MONTH(i.BillingDate) >= 4
                 THEN YEAR(i.BillingDate)
                 ELSE YEAR(i.BillingDate) - 1 END AS FYStart,
            SUM(item.BilledQty) AS TotalQuantity
        FROM InvoiceDates AS i
        INNER JOIN dbo.TB_InvoiceItemDetails AS item
            ON item.BillingDocument = i.BillingDocument
        GROUP BY CASE WHEN MONTH(i.BillingDate) >= 4
                      THEN YEAR(i.BillingDate)
                      ELSE YEAR(i.BillingDate) - 1 END
    )
    SELECT
        'FY' + RIGHT(CONVERT(VARCHAR(4), FYStart), 2) AS FinancialYear,
        ISNULL(SUM(TotalValue), 0) AS TotalValue,
        ISNULL(SUM(TotalQuantity), 0) AS TotalQuantity
    FROM
    (
        SELECT FYStart, TotalValue, CAST(0 AS DECIMAL(38,6)) AS TotalQuantity FROM InvoiceValues
        UNION ALL
        SELECT FYStart, CAST(0 AS DECIMAL(38,2)) AS TotalValue, TotalQuantity FROM InvoiceQuantities
    ) AS fy
    GROUP BY FYStart
    ORDER BY FinancialYear;
END;
GO
