--Create Table to insert CSV file
CREATE TABLE county_health_data (
    Year INT,
    StateAbbr VARCHAR(2),
    StateDesc VARCHAR(50),
    LocationName VARCHAR(100),
    DataSource VARCHAR(20),
    Category VARCHAR(50),
    Measure VARCHAR(100),
    Data_Value_Unit VARCHAR(10),
    Data_Value_Type VARCHAR(50),
    Data_Value FLOAT,
    Data_Value_Footnote_Symbol VARCHAR(5),
    Data_Value_Footnote TEXT,
    Low_Confidence_Limit FLOAT,
    High_Confidence_Limit FLOAT,
    TotalPopulation INT,
    TotalPop18plus INT,
    LocationID INT,
    CategoryID VARCHAR(10),
    MeasureId VARCHAR(20),
    DataValueTypeID VARCHAR(10),
    Short_Question_Text VARCHAR(100),
    Geolocation VARCHAR(100)
);
---------------------------------------------------

--Preview dataset columns as imported from csv file
SELECT TOP 5 *
FROM county_health_data;


-- Footnotes columns are sparsely populated (14 out of 20k+ rows); not meaningful for analysis
SELECT Data_Value_Footnote, Data_Value_Footnote_Symbol, COUNT(*) AS 'Row CNT'
FROM county_health_data
WHERE Data_Value_Footnote_Symbol IS NOT NULL AND Data_Value_Footnote IS NOT NULL
GROUP BY Data_Value_Footnote, Data_Value_Footnote_Symbol;

-- These columns contain only 1-2 unique values and are not informative for analysis or visualization
SELECT DISTINCT DataValueTypeID, DataSource, Data_Value_Unit, Data_Value_Type, COUNT(*) AS 'Row CNT'
FROM county_health_data
GROUP BY DataSource, Data_Value_Unit, Data_Value_Type, DataValueTypeID;

-- Dropping non-informative or redundant columns: footnotes, DataValueTypeID, Data_Value_Unit, and DataSource
ALTER TABLE county_health_data
DROP COLUMN Data_Value_Footnote, Data_Value_Footnote_Symbol, DataValueTypeID, DataSource, Data_Value_Unit, Data_Value_Type;

--Preview to ensure columns were dropped as expected
SELECT TOP 5 *
FROM county_health_data;
-------------------------------------

--Perform column inspection and cleaning setup for later analysis
    
SELECT TOP 5 *
FROM county_health_data;

-- StateDesc is functionally redundant with StateAbbr (both show 52 unique values); may keep for visualization labels
SELECT COUNT(DISTINCT StateAbbr) AS 'State Abr', COUNT(DISTINCT StateDesc) AS 'State Desc'
FROM county_health_data;

-- Category is concise and readable; CategoryID is more technical and may be dropped if not needed in joins
SELECT CategoryID, Category, COUNT(*) AS 'Row CNT'
FROM county_health_data
GROUP BY CategoryID, Category;

-- Assessing redundancy among MeasureId, Measure, and Short_Question_Text to determine which to retain
SELECT DISTINCT MeasureId, Measure, Short_Question_Text, COUNT(*) AS 'Row CNT'
FROM county_health_data
GROUP BY MeasureId, Measure, Short_Question_Text;

-- Short_Question_Text typically summarizes Measure/MeasureID, 
-- but a few measures omit age ranges — CASE logic is used to append age context for clarity
SELECT DISTINCT MeasureId, Short_Question_Text,
                CASE MeasureId
                    WHEN 'ACCESS2' THEN CONCAT(Short_Question_Text, ' (18-64 yrs)')
                    WHEN 'TEETHLOST' THEN CONCAT(Short_Question_Text, ' (65+ yrs)')
                    WHEN 'COLON_SCREEN' THEN CONCAT(Short_Question_Text, ' (45–75 yrs)')
                    WHEN 'MAMMOUSE' THEN CONCAT(Short_Question_Text, ' (Women 50-74 yrs)')
                    ELSE Short_Question_Text
                    END AS Adjusted_Short_Question_Text
FROM county_health_data;

SELECT DISTINCT Year, COUNT(*) AS 'Row CNT'
FROM county_health_data
GROUP BY Year;


--Creating our VIEWS 
-- 1. Cleaned columns (e.g., after dropping verbose ones)
CREATE VIEW vw_CleanedColumns AS
SELECT
    Year, StateAbbr, StateDesc, LocationName, Geolocation,
    Category,MeasureId,Short_Question_Text,Data_Value,
    Low_Confidence_Limit, High_Confidence_Limit, TotalPopulation, TotalPop18plus
FROM county_health_data;

-- 2. Adjusted question text
CREATE VIEW vw_AdjustedQuestions AS
SELECT *,
       CASE MeasureId
           WHEN 'ACCESS2' THEN CONCAT(Short_Question_Text, ' (18-64 yrs)')
           WHEN 'TEETHLOST' THEN CONCAT(Short_Question_Text, ' (65+ yrs)')
           WHEN 'COLON_SCREEN' THEN CONCAT(Short_Question_Text, ' (45–75 yrs)')
           WHEN 'MAMMOUSE' THEN CONCAT(Short_Question_Text, ' (Women 50-74 yrs)')
           ELSE Short_Question_Text
           END AS Measure_Description
FROM vw_CleanedColumns;

-- 3.Final master view that includes formatted Margin of Error
ALTER VIEW vw_MasterHealthView AS
SELECT Year, StateAbbr, LocationName, Category, MeasureId, Measure_Description, Data_Value AS 'Measure_Value', TotalPopulation, TotalPop18plus, 
       ROUND((High_Confidence_Limit - Low_Confidence_Limit) / 2.0, 3) AS Margin_of_Error,
       TRY_CAST(
               SUBSTRING(
                       SUBSTRING(Geolocation, 8, LEN(Geolocation) - 8 - 1),  -- inner string without "POINT (" and ")"
                       1,
                       CHARINDEX(' ', SUBSTRING(Geolocation, 8, LEN(Geolocation) - 8 - 1)) - 1
               )
           AS FLOAT
       ) AS Longitude,
       TRY_CAST(
               SUBSTRING(
                       SUBSTRING(Geolocation, 8, LEN(Geolocation) - 8 - 1),
                       CHARINDEX(' ', SUBSTRING(Geolocation, 8, LEN(Geolocation) - 8 - 1)) + 1,
                       LEN(SUBSTRING(Geolocation, 8, LEN(Geolocation) - 8 - 1))
               )
           AS FLOAT
       ) AS Latitude
FROM vw_AdjustedQuestions;

SELECT Measure_Description, COUNT(*) AS 'Row CNT'
FROM vw_MasterHealthView
group by Measure_Description
ORDER BY 2 DESC;

-- Creating a chronic conditions pivot view 
ALTER VIEW vw_HealthRisksPivot AS
SELECT 
    StateAbbr, LocationName, Latitude, Longitude,
    ROUND([DIABETES], 2) AS [Diabetes], 
    ROUND([CHD], 2) AS [Coronary Heart Disease],
    ROUND([OBESITY], 2) AS [Obesity],
    ROUND([LPA], 2) AS [Physical Inactivity],
    ROUND([BPHIGH], 2) AS [High Blood Pressure],
    ROUND([HIGHCHOL], 2) AS [High Cholesterol]
FROM (
    SELECT 
        StateAbbr,
        LocationName,
        Latitude,
        Longitude,
        MeasureId,
        Measure_Value
    FROM vw_MasterHealthView
    WHERE MeasureId IN ('DIABETES', 'CHD', 'OBESITY', 'LPA', 'BPHIGH', 'HIGHCHOL')
) AS SourceTable
PIVOT (
    AVG(Measure_Value) FOR MeasureId IN ([DIABETES], [CHD], [OBESITY], [LPA], [BPHIGH], [HIGHCHOL])
) AS PivotedData;

--Preview pivot to ensure accuracy 
SELECT TOP 5 * 
FROM vw_HealthRisksPivot

-- Creating a resource access pivot view
ALTER VIEW vw_ResourceAccessPivot AS
SELECT
    StateAbbr,
    LocationName,
    Latitude,
    Longitude,
    ROUND([ACCESS2], 2) AS [No Health Insurance],
    ROUND([CHECKUP], 2) AS [Annual Checkup],
    ROUND([FOODINSECU], 2) AS [Food Insecurity],
    ROUND([HOUSINSECU], 2) AS [Housing Insecurity],
    ROUND([SHUTUTILITY], 2) AS [Utility Shut-off Threat],
    ROUND([LACKTRPT], 2) AS [Lack of Reliable Transportation],
    ROUND([FOODSTAMP], 2) AS [Received Food Stamps],
    ROUND([INDEPLIVE], 2) AS [Independent Living Disability]
FROM (
    SELECT
        StateAbbr,
        LocationName,
        Latitude,
        Longitude,
        MeasureId,
        Measure_Value
    FROM vw_MasterHealthView
    WHERE MeasureId IN (
        'ACCESS2', 'CHECKUP', 'FOODINSECU', 'HOUSINSECU',
        'SHUTUTILITY', 'LACKTRPT', 'FOODSTAMP', 'INDEPLIVE'
    )
) AS SourceTable
PIVOT (
    AVG(Measure_Value) FOR MeasureId IN (
        [ACCESS2], [CHECKUP], [FOODINSECU], [HOUSINSECU],
        [SHUTUTILITY], [LACKTRPT], [FOODSTAMP], [INDEPLIVE]
    )
) AS PivotedData;

-- Preview resource access pivot view to ensure accuracy
SELECT TOP 5 * 
FROM vw_ResourceAccessPivot;

-- Creating a mental health pivot view
ALTER VIEW vw_MentalHealthPivot AS
SELECT
    StateAbbr, 
    LocationName, 
    Latitude, 
    Longitude,
    ROUND([DEPRESSION], 2) AS [Depression],
    ROUND([MHLTH], 2) AS [Frequent Mental Distress],
    ROUND([PHLTH], 2) AS [Frequent Physical Distress],
    ROUND([ISOLATION], 2) AS [Social Isolation],
    ROUND([EMOTIONSPT], 2) AS [Lack of Social and Emotional Support],
    ROUND([SLEEP], 2) AS [Short Sleep Duration]
FROM (
    SELECT 
        StateAbbr,
        LocationName,
        Latitude,
        Longitude,
        MeasureId,
        Measure_Value
    FROM vw_MasterHealthView
    WHERE MeasureId IN (
        'DEPRESSION', 'MHLTH', 'PHLTH', 'ISOLATION', 'EMOTIONSPT', 'SLEEP'
    )
) AS SourceTable
PIVOT (
    AVG(Measure_Value) FOR MeasureId IN (
        [DEPRESSION], [MHLTH], [PHLTH], [ISOLATION], [EMOTIONSPT], [SLEEP]
    )
) AS PivotedData;

-- Preview mental health pivot view to ensure accuracy
SELECT TOP 5 *
FROM vw_MentalHealthPivot;
