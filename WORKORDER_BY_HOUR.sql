CREATE view [dbo].[VwMaintenanceWorkOrderByHour] as 

with datetimetable as (
select [DateTime] 
      ,[Date]
      ,[Time]
      ,[Hour24Name]
      ,[Shift]
  FROM [BPS_DM].[dbo].[DimDateTime] 
  where datetime >=  DATEADD(MONTH,-6,CAST(CAST(GETDATE() AS DATE) AS DATETIME)) and datetime<= CAST(GETDATE() as datetime)
)

, WorkOrderData  AS	(
	SELECT
		wo.[WONum],
		wo.[WorkOrderID],
		wo.[ActStart],
		wo.[ActFinish],
		wo.[SchedStart],
		wo.[SchedFinish],
		wo.[Parent],	
		wo.[Status],
		wt.WorkTypeBusKey,
		wo.[mxkResMaintdep],
		a.AssetNumBusKey,
		l.LocationBusKey,
		WO.[RouteKey],
		wo.[HasChildren],
		wo.[dpmc_CostCode],
		wo.[Description]
		,DATEADD(hour, DATEDIFF(hour, 0, actstart), 0) as ActualStartHour    -- rounding down to closest hour, we need it so we can capture wo's that started after the full hour i.e. at 14:20 
		,DATEADD(hour, DATEDIFF(hour, 0, schedstart), 0) as ScheduledStartHour

		-- added 13.05.2022
		,wo.SiteID
		,wo.WOClass
	FROM [BPS_DM].[dbo].FactMaintenanceWorkOrder WO
			JOIN [BPS_DM].[dbo].DimAsset A ON WO.AssetKey = A.AssetKey
			JOIN [BPS_DM].[dbo].DimWorkType WT ON WO.WorkTypeKey = WT.WorkTypeKey
			JOIN [BPS_DM].[dbo].DimLocations L ON WO.LocationKey = L.LocationKey
	WHERE [WOClass] = 'WORKORDER'
)


, WorkOrderActualHourly as (  --generating one row per date and hour for each wo according to its actual window
	SELECT
		HCAL.[DateTime],
		HCAL.[Date],
		HCAL.[Hour24Name],
		HCAL.[Shift],
		WO.[WorkOrderID],
		wo.[ActStart],
		wo.[ActFinish]
		,cast(case when actstart > [DATETIME] and Cast((actfinish - [DATETIME]) as Float) * 24.0 > 1 then cast(cast(DATEDIFF (MINUTE,actstart,DATEADD(HOUR,1,[DATETIME]))  as numeric(18,2)) / 60 as numeric(18,2))
				  when actstart > [DATETIME] and Cast((actfinish - [DATETIME]) as Float) * 24.0 <= 1 then cast(cast(DATEDIFF (MINUTE,actstart,ActFinish)  as numeric(18,2)) / 60 as numeric(18,2))
				  when actstart <= [DATETIME] and Cast((actfinish - [DATETIME]) as Float) * 24.0 > 1 then  cast(cast(DATEDIFF (MINUTE,[DATETIME],DATEADD(HOUR,1,[DATETIME]))  as numeric(18,2)) / 60 as numeric(18,2))
			 else cast(cast(DATEDIFF (MINUTE,[DATETIME],actfinish)  as numeric(18,2)) / 60 as numeric(18,2))  end  AS NUMERIC (15,2)) as [ActualHours] 
	FROM WorkOrderData WO
	JOIN datetimetable HCAL ON HCAL.[DateTime] >= ActualStartHour AND HCAL.[DateTime] < [ActFinish]
	WHERE [ActStart] IS NOT NULL 
)



,WorkOrderScheduledHourly	AS (	--generating one row per date and hour for each wo according to its scheduled window
	SELECT
		HCAL.[DateTime],
		HCAL.[Date],
		HCAL.[Hour24Name],
		HCAL.[Shift],
		WO.workorderid,
			cast(case when schedstart > [DATETIME] and Cast((schedfinish - [DATETIME]) as Float) * 24.0 > 1 then cast(cast(DATEDIFF (MINUTE,schedstart,DATEADD(HOUR,1,[DATETIME]))  as numeric(18,2)) / 60 as numeric(18,2))
				  when schedstart > [DATETIME] and Cast((schedfinish - [DATETIME]) as Float) * 24.0 <= 1 then cast(cast(DATEDIFF (MINUTE,schedstart,schedfinish)  as numeric(18,2)) / 60 as numeric(18,2))
				  when schedstart <= [DATETIME] and Cast((schedfinish - [DATETIME]) as Float) * 24.0 > 1 then  cast(cast(DATEDIFF (MINUTE,[DATETIME],DATEADD(HOUR,1,[DATETIME]))  as numeric(18,2)) / 60 as numeric(18,2))
			 else cast(cast(DATEDIFF (MINUTE,[DATETIME],schedfinish)  as numeric(18,2)) / 60 as numeric(18,2))  end  AS NUMERIC (15,2)) as [ScheduledHours]
	FROM WorkOrderData WO
	JOIN datetimetable HCAL ON HCAL.[DateTime] >= ScheduledStartHour AND HCAL.[DateTime] < [SchedFinish]
	WHERE [SchedStart] IS NOT NULL --we disregard rows where we do not have an actual schedstart date
)


, WorkOrderBase  AS ( --this the colection of all date+hour timestamps for both act and scheduled timestamps generated above - we want to remove duplicates (UNION) as we have only 1 line if there is ACT and SCHED hours
	SELECT 		[DateTime],[Date],[Hour24Name],[Shift],[WorkOrderID]	FROM WorkOrderActualHourly
	UNION
	SELECT 		[DateTime],[Date],[Hour24Name],[Shift],[WorkOrderID]	FROM WorkOrderScheduledHourly
)


SELECT 
	FWO.SiteID, 
	FWO.WOClass, 
	WO.[DateTime],
	WO.[Date],
	WO.[Hour24Name],
	WO.[Shift],
	FWO.[WorkOrderID],
	FWO.[Parent],
	FWO.[WONum],
	FWO.[Status],
	FWO.WorkTypebusKey as WorkType,
	FWO.[mxkResMaintdep] as [MxkResMaintDep],
	FWO.assetnumbuskey as AssetNum,
	FWO.locationbuskey as [Location],
	FWO.[dpmc_CostCode] as [DpmcCostCode],
	FWO.[Description],
	FWO.[RouteKey],
	FWO.[HasChildren],
	FWO.[SchedStart],
	FWO.[SchedFinish],
	FWO.[ActStart],
	FWO.[ActFinish],
	ACT.[ActualHours],
	SCH.[ScheduledHours]

	
FROM WorkOrderBase WO
JOIN WorkOrderData FWO ON WO.workorderid = FWO.workorderid										-- get all the details needed per WO
LEFT JOIN WorkOrderActualHourly ACT ON WO.workorderid = ACT.workorderid AND WO.DATETIME = ACT.DATETIME   --left join not all timestamps have actual data - some have entries only for scheduled
LEFT JOIN WorkOrderScheduledHourly SCH ON WO.workorderid = SCH.workorderid AND WO.DATETIME = SCH.DATETIME	 --left join not all timestamps have scheduled data - some have entries only for actual





GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Site ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'SiteID'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Work order class' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'WOClass'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Date and Time' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'DateTime'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Date' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Date'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Hour 24 hour format' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Hour24Name'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Shift' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Shift'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Work Order ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'WorkOrderID'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Parent' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Parent'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'WO Number' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'WONum'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Status' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Status'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Work Type' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'WorkType'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mxk Res Maintenance Department' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'MxkResMaintDep'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Asset Number' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'AssetNum'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Location' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Location'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Chelopech Cost Code' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'DpmcCostCode'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Description' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'Description'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Route Key' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'RouteKey'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Has Children' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'HasChildren'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Scheduled Start' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'SchedStart'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Scheduled Finish' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'SchedFinish'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Act Start' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'ActStart'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Act Finish' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'ActFinish'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Actual Hours' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'ActualHours'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Scheduled Hours' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour', @level2type=N'COLUMN',@level2name=N'ScheduledHours'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'This view represents data from BGMaximoWorkOrder broken down by hour.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'VwMaintenanceWorkOrderByHour'
GO


