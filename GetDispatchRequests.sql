USE [SalesOrderUAT]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetAllDispatchRequests]    Script Date: 12-09-2026 2.56.01 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[usp_GetAllDispatchRequests]
(
    @UserCode NVARCHAR(50),
    @PageNumber INT = 1,
    @PageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    ------------------------------------------------------------
    -- Validate pagination
    ------------------------------------------------------------
    IF @PageNumber IS NULL OR @PageNumber < 1
        SET @PageNumber = 1;

    IF @PageSize IS NULL OR @PageSize < 1
        SET @PageSize = 10;

    IF @PageSize > 100
        SET @PageSize = 100;


    ------------------------------------------------------------
    -- Variables
    ------------------------------------------------------------
    DECLARE @RoleId INT;
    DECLARE @Offset INT;
    DECLARE @CanViewAll BIT = 0;

    SET @Offset = (@PageNumber - 1) * @PageSize;


    ------------------------------------------------------------
    -- Find RoleId of logged-in user
    ------------------------------------------------------------
    SELECT
        @RoleId = U.RoleId
    FROM dbo.Users U
    WHERE U.UserCode = @UserCode;


    ------------------------------------------------------------
    -- Temporary table containing allowed customers
    ------------------------------------------------------------
    CREATE TABLE #AllowedCustomers
    (
        CustomerCode NVARCHAR(50) NOT NULL
            PRIMARY KEY
    );


    ------------------------------------------------------------
    -- User not found
    ------------------------------------------------------------
    IF @RoleId IS NULL
    BEGIN

        SELECT
            CAST(0 AS INT) AS TotalRecords;

        SELECT
            DR.Id,
            DR.CustomerCode,
            DR.OrderNumber,
            DR.ProductId,
            DR.ItemId,
            DR.PriceCardType,
            DR.PricePerKg,
            DR.BookingPrice,
            DR.BookedQty,
            DR.BookingAmtPaid,
            DR.BalanceAmtToPay,
            DR.BalanceQuantity,
            DR.DispatchStatus,
            DR.RequestForQuantityMT,
            DR.AmountRequiredToDispatch,
            DR.BookingAmountReceived,
            DR.BalanceAmount,
            DR.FromDate,
            DR.ToDate,
            DR.DispatchAddress,
            DR.CreatedOn
        FROM dbo.DispatchRequests DR
        WHERE 1 = 0;

        RETURN;
    END;


    ------------------------------------------------------------
    -- ROLE 1 : CUSTOMER
    ------------------------------------------------------------
    IF @RoleId = 1
    BEGIN

        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT @UserCode;

    END


    ------------------------------------------------------------
    -- ROLE 2 : TM
    ------------------------------------------------------------
    ELSE IF @RoleId = 2
    BEGIN

        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT DISTINCT
            C.CustomerCode
        FROM dbo.TB_CustomerMaster C
        WHERE C.TM = @UserCode
          AND C.CustomerCode IS NOT NULL;

    END


    ------------------------------------------------------------
    -- ROLE 3 : RM
    ------------------------------------------------------------
    ELSE IF @RoleId = 3
    BEGIN

        /*
            Normal hierarchy:

            RM
             |
             +---- TM
                    |
                    +---- Customer
        */

        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT DISTINCT
            C.CustomerCode
        FROM dbo.TB_CustomerMaster C
        INNER JOIN dbo.Users TM
            ON TM.UserCode = C.TM
        WHERE TM.RepManCode = @UserCode
          AND TM.RoleId = 2
          AND C.CustomerCode IS NOT NULL;


        --------------------------------------------------------
        -- Also support customers directly mapped using
        -- RM UserCode in TM column, if such old data exists.
        --------------------------------------------------------
        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT DISTINCT
            C.CustomerCode
        FROM dbo.TB_CustomerMaster C
        WHERE C.TM = @UserCode
          AND C.CustomerCode IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM #AllowedCustomers AC
              WHERE AC.CustomerCode = C.CustomerCode
          );

    END


    ------------------------------------------------------------
    -- ROLE 4 : ZM
    ------------------------------------------------------------
    ELSE IF @RoleId = 4
    BEGIN

        /*
            Case 1:

            ZM
             |
             +---- RM
                    |
                    +---- TM
                           |
                           +---- Customer
        */

        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT DISTINCT
            C.CustomerCode
        FROM dbo.TB_CustomerMaster C

        INNER JOIN dbo.Users TM
            ON TM.UserCode = C.TM
           AND TM.RoleId = 2

        INNER JOIN dbo.Users RM
            ON RM.UserCode = TM.RepManCode
           AND RM.RoleId = 3

        WHERE RM.RepManCode = @UserCode
          AND C.CustomerCode IS NOT NULL;


        --------------------------------------------------------
        -- Case 2 : RM is NOT present
        --
        -- ZM
        --  |
        --  +---- TM
        --         |
        --         +---- Customer
        --------------------------------------------------------

        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT DISTINCT
            C.CustomerCode
        FROM dbo.TB_CustomerMaster C

        INNER JOIN dbo.Users TM
            ON TM.UserCode = C.TM
           AND TM.RoleId = 2

        WHERE TM.RepManCode = @UserCode
          AND C.CustomerCode IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM #AllowedCustomers AC
              WHERE AC.CustomerCode = C.CustomerCode
          );


        --------------------------------------------------------
        -- Optional fallback for old/direct mapping
        --------------------------------------------------------

        INSERT INTO #AllowedCustomers
        (
            CustomerCode
        )
        SELECT DISTINCT
            C.CustomerCode
        FROM dbo.TB_CustomerMaster C

        WHERE C.TM = @UserCode
          AND C.CustomerCode IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM #AllowedCustomers AC
              WHERE AC.CustomerCode = C.CustomerCode
          );

    END


    ------------------------------------------------------------
    -- ROLE > 4
    -- Can see every dispatch request
    ------------------------------------------------------------
    ELSE IF @RoleId > 4
    BEGIN

        SET @CanViewAll = 1;

    END


    ------------------------------------------------------------
    -- TOTAL RECORD COUNT
    ------------------------------------------------------------
    SELECT
        COUNT(1) AS TotalRecords
    FROM dbo.DispatchRequests DR
    WHERE
        @CanViewAll = 1

        OR EXISTS
        (
            SELECT 1
            FROM #AllowedCustomers AC
            WHERE AC.CustomerCode = DR.CustomerCode
        );


    ------------------------------------------------------------
    -- PAGINATED DISPATCH REQUEST DATA
    ------------------------------------------------------------
    SELECT
        DR.Id,
        DR.CustomerCode,
        DR.OrderNumber,
        DR.ProductId,
        DR.ItemId,
        DR.PriceCardType,
        DR.PricePerKg,
        DR.BookingPrice,
        DR.BookedQty,
        DR.BookingAmtPaid,
        DR.BalanceAmtToPay,
        DR.BalanceQuantity,
        DR.DispatchStatus,
        DR.RequestForQuantityMT,
        DR.AmountRequiredToDispatch,
        DR.BookingAmountReceived,
        DR.BalanceAmount,
        DR.FromDate,
        DR.ToDate,
        DR.DispatchAddress,
        DR.CreatedOn

    FROM dbo.DispatchRequests DR

    WHERE
        @CanViewAll = 1

        OR EXISTS
        (
            SELECT 1
            FROM #AllowedCustomers AC
            WHERE AC.CustomerCode = DR.CustomerCode
        )

    ------------------------------------------------------------
    -- IMPORTANT:
    -- NO DispatchStatus condition.
    --
    -- Partial
    -- Complete
    -- Pending
    -- Any other status
    --
    -- All will be returned.
    ------------------------------------------------------------

    ORDER BY
        DR.CreatedOn DESC,
        DR.Id DESC

    OFFSET @Offset ROWS

    FETCH NEXT @PageSize ROWS ONLY;

END
GO

