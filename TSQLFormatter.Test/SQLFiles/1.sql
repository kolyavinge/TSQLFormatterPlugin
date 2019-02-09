IF EXISTS (SELECT * FROM sys.objects WHERE OBJECT_ID = OBJECT_ID(N'[dbo].[ImportMisTourStop]') AND TYPE IN (N'P', N'PC'))
    DROP PROCEDURE [dbo].[ImportMisTourStop]
GO

CREATE PROCEDURE [dbo].[ImportMisTourStop] (@mq_Id INT)
AS
BEGIN

DECLARE @mq_date            DATETIME,
        @mq_hotelKey        INT,
		@mq_roomKey         INT,
		@mq_roomCategoryKey INT,
        @mq_tourKey         INT

SELECT TOP 1 @mq_date = MQ_Date, @mq_hotelKey = MQ_HotelKey, @mq_roomKey = MQ_RoomKey, @mq_roomCategoryKey = MQ_RoomCategoryKey, @mq_tourKey = MQ_TourKey
FROM MIS_Quotas WITH(NOLOCK)
WHERE MQ_Id = @mq_Id

-- таблица с ключами цен, которые затрагиваются этим стопом
CREATE TABLE #TmpCosts
(
    XId      INT NOT NULL PRIMARY KEY,
	XDateBeg DATETIME,
	XDateEnd DATETIME
)

-- берем ключи цен, которые затрагиваются этим стопом
INSERT INTO #TmpCosts (XId, XDateBeg, XDateEnd)
SELECT CS_ID, CS_Date, CS_DateEnd
FROM tbl_Costs WITH(NOLOCK)
WHERE CS_SVKey = 3
    AND CS_Code = @mq_hotelKey
	AND @mq_date BETWEEN CS_DateBeg AND CS_DateEnd
	AND CS_TRKey = @mq_tourKey
	AND EXISTS (SELECT TOP 1 1 FROM HotelRooms WITH(NOLOCK) WHERE HR_Key = CS_SubCode1 AND HR_RMKey = @mq_roomKey AND HR_RCKey = @mq_roomCategoryKey)

-- обновляем период продаж у однодневных цен
UPDATE tbl_Costs
SET cs_DateSellBeg = '2000-01-01', cs_DateSellEnd = '2000-01-01'
WHERE CS_ID IN (SELECT XId FROM #TmpCosts WHERE XDateBeg = XDateEnd)

-- создаем цены с прошедшей датой продажи и датой действия равной дате стопа
INSERT INTO tbl_Costs ([CS_SVKEY],[CS_CODE],[CS_SUBCODE1],[CS_SUBCODE2],[CS_PRKEY],[CS_PKKEY],[CS_DATE],[CS_DATEEND],[CS_WEEK],[CS_COSTNETTO],[CS_COST],[CS_DISCOUNT],[CS_TYPE],[CS_CREATOR],[CS_RATE],[CS_UPDDATE],[CS_LONG],[CS_BYDAY],[CS_FIRSTDAYNETTO],[CS_FIRSTDAYBRUTTO],[CS_PROFIT],[CS_CINNUM],[CS_TypeCalc],[cs_DateSellBeg],[cs_DateSellEnd],[CS_CHECKINDATEBEG],[CS_CHECKINDATEEND],[CS_LONGMIN],[CS_TypeDivision],[CS_UPDUSER],[CS_TRFId],[CS_COID])
SELECT                ([CS_SVKEY],[CS_CODE],[CS_SUBCODE1],[CS_SUBCODE2],[CS_PRKEY],[CS_PKKEY], @mq_date,    @mq_date,[CS_WEEK],[CS_COSTNETTO],[CS_COST],[CS_DISCOUNT],[CS_TYPE],[CS_CREATOR],[CS_RATE],[CS_UPDDATE],[CS_LONG],[CS_BYDAY],[CS_FIRSTDAYNETTO],[CS_FIRSTDAYBRUTTO],[CS_PROFIT],[CS_CINNUM],[CS_TypeCalc],    '2000-01-01',    '2000-01-01',[CS_CHECKINDATEBEG],[CS_CHECKINDATEEND],[CS_LONGMIN],[CS_TypeDivision],[CS_UPDUSER],[CS_TRFId],[CS_COID])
FROM tbl_Costs WITH(NOLOCK)
WHERE CS_ID IN (SELECT XId FROM #TmpCosts WHERE XDateBeg != XDateEnd)

-- двигаем дату начала действия у тех цен, у которых дата начала совпадает с датой стопа
UPDATE tbl_Costs
SET CS_Date = DATEADD(DAY, 1, CS_Date)
WHERE CS_ID IN (SELECT XId FROM #TmpCosts WHERE XDateBeg = @mq_date AND XDateBeg != XDateEnd)

-- двигаем дату конца действия у тех цен, у которых дата конца совпадает с датой стопа
UPDATE tbl_Costs
SET CS_DateEnd = DATEADD(DAY, -1, CS_DateEnd)
WHERE CS_ID IN (SELECT XId FROM #TmpCosts WHERE XDateEnd = @mq_date AND XDateBeg != XDateEnd)

-- обрабатываем цены, которые разбиваются на две
-- сначала двигаем дату конца цены, чтобы стоп шел после нее
UPDATE tbl_Costs
SET CS_DateEnd = DATEADD(DAY, -1, @mq_date)
WHERE CS_ID IN (SELECT XId FROM #TmpCosts WHERE XDateBeg != @mq_date AND XDateEnd != @mq_date)

-- потом создаем новые цены, с датой начала перед стопом
INSERT INTO tbl_Costs ([CS_SVKEY],[CS_CODE],[CS_SUBCODE1],[CS_SUBCODE2],[CS_PRKEY],[CS_PKKEY],                [CS_DATE],[CS_DATEEND],[CS_WEEK],[CS_COSTNETTO],[CS_COST],[CS_DISCOUNT],[CS_TYPE],[CS_CREATOR],[CS_RATE],[CS_UPDDATE],[CS_LONG],[CS_BYDAY],[CS_FIRSTDAYNETTO],[CS_FIRSTDAYBRUTTO],[CS_PROFIT],[CS_CINNUM],[CS_TypeCalc],[cs_DateSellBeg],[cs_DateSellEnd],[CS_CHECKINDATEBEG],[CS_CHECKINDATEEND],[CS_LONGMIN],[CS_TypeDivision],[CS_UPDUSER],[CS_TRFId],[CS_COID])
SELECT                ([CS_SVKEY],[CS_CODE],[CS_SUBCODE1],[CS_SUBCODE2],[CS_PRKEY],[CS_PKKEY],DATEADD(DAY, 1, @mq_date),[CS_DATEEND],[CS_WEEK],[CS_COSTNETTO],[CS_COST],[CS_DISCOUNT],[CS_TYPE],[CS_CREATOR],[CS_RATE],[CS_UPDDATE],[CS_LONG],[CS_BYDAY],[CS_FIRSTDAYNETTO],[CS_FIRSTDAYBRUTTO],[CS_PROFIT],[CS_CINNUM],[CS_TypeCalc],[cs_DateSellBeg],[cs_DateSellEnd],[CS_CHECKINDATEBEG],[CS_CHECKINDATEEND],[CS_LONGMIN],[CS_TypeDivision],[CS_UPDUSER],[CS_TRFId],[CS_COID])
FROM tbl_Costs WITH(NOLOCK)
WHERE CS_ID IN (SELECT XId FROM #TmpCosts WHERE XDateBeg != @mq_date AND XDateEnd != @mq_date)

DROP TABLE #TmpCosts

END
GO

GRANT EXEC ON [dbo].[ImportMisTourStop] TO PUBLIC
GO