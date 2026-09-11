/****** Object:  Table [dbo].[TB_CustomerLedger]    Script Date: 9/12/2026 3:43:57 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[TB_CustomerLedger](
	[CompanyCode] [bigint] NULL,
	[CustomerCode] [nvarchar](50) NULL,
	[Document_Type] [nvarchar](50) NULL,
	[Document_Number] [nvarchar](50) NULL,
	[Credit_Control_Area] [nvarchar](50) NULL,
	[Document_Date] [date] NULL,
	[Net_Due_Date] [date] NULL,
	[Posting_Date] [date] NULL,
	[Credit_Control_Area_Currency] [nvarchar](50) NULL,
	[Baseline_Payment_Date] [date] NULL,
	[Amount_in_Local_Currency] [decimal](18, 0) NULL,
	[Clearing_Date] [date] NULL,
	[Clearing_Document] [nvarchar](50) NULL,
	[Assignment] [nvarchar](30) NULL,
	[Reference] [nvarchar](50) NULL,
	[Text] [nvarchar](255) NULL,
	[Account] [nvarchar](50) NULL,
	[Document_Header_Text] [nvarchar](255) NULL,
	[UserCode] [nvarchar](50) NULL,
	[Arrears_by_Net_Due_Date] [bigint] NULL,
	[GLAccount] [varchar](50) NULL,
	[UpdateBy] [nvarchar](max) NULL,
	[DC] [nvarchar](5) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

