USE [Admin]
GO

CREATE SCHEMA [Repo]
GO


/****** Object:  Table [Repo].[ObjectsRepository]    Script Date: 8/17/2015 9:40:39 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [Repo].[ObjectsRepository](
	[ObjectRowID] [int] IDENTITY(1,1) NOT NULL,
	[ServerName] [varchar](150) NULL,
	[DBContext] [varchar](150) NULL,
	[CaptureDate] [datetime] NULL,
	[ObjectID] [int] NULL,
	[ObjectFullName] [varchar](255) NULL,
	[ObjectSchemaName] [varchar](125) NULL,
	[ObjectName] [varchar](255) NULL,
	[ObjectType] [varchar](25) NULL,
	[ObjectCode] [varchar](max) NULL,
	[ObjectCreateDate] [datetime] NULL,
	[ObjectModifiedDate] [datetime] NULL,
 CONSTRAINT [PK_ObjectsRepository] PRIMARY KEY CLUSTERED 
(
	[ObjectRowID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO


