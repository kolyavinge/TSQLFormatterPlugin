IF EXISTS (SELECT * FROM sys.objects WHERE OBJECT_ID = OBJECT_ID(N'[dbo].[ImportMisQuota]') AND TYPE IN (N'P', N'PC'))
    DROP PROCEDURE [dbo].[ImportMisQuota]
GO

--1)
--МТ, Экран квоты: 2 занято, 0 свободно
--МИС: Отправляем 0
--Итог: 0 занято, -2 свободно, идет письмо

--2)
--МТ: 0 занято, 0 свободно
--МИС: Отправляем 0
--Итог: квота в МТ должна удалиться

--3)
--МТ: Экран квоты: 4 занято
--МИС: Отправляем 2
--Итог: 2 занято, -2 свободно, идет письмо


CREATE PROCEDURE [dbo].[ImportMisQuota]
(
    @mq_Id  INT = NULL           -- ключ записи в MisQuotas
)
AS
BEGIN
	DECLARE @qtid INT,
			@qoid INT,
			@qpid INT,
			@qdid INT,
			@stid INT,
			@qdbusy INT,
			@uskey INT,
            @partnerName VARCHAR(100),
			@ss_allotmentAndCommitment INT,
            @qdtype INT,
			@mq_PartnerKey INT,
			@mq_HotelKey INT,
			@mq_RoomCategoryKey INT,
			@mq_RoomKey INT,
			@mq_FlightKey INT,
			@mq_AirServiceKey INT,
			@mq_Date DATETIME,
            @mq_Places INT,
			@mq_QuotaType INT,
			@mq_Release INT,
			@mq_ImportType INT,
            @mq_IsByCheckin BIT,    -- признак "запрет заезда"
			@mq_svkey INT,
			@flightCityKeyFrom int

	declare @isMT11 int
	select @isMT11 = SS_ParmValue from SystemSettings where SS_ParmName = 'NewReCalculatePrice'

	Select  @mq_PartnerKey = Mq_PartnerKey,
			@mq_HotelKey = MQ_HotelKey,
			@mq_RoomCategoryKey = MQ_RoomCategoryKey,
			@mq_RoomKey = MQ_RoomKey,
			@mq_FlightKey = MQ_FlightKey,
			@mq_AirServiceKey = MQ_AirServiceKey,
			@mq_Date = MQ_Date,
			@mq_Places = MQ_Places,
			@mq_QuotaType = MQ_QuotaType,
			@mq_Release = MQ_Release,
			@mq_IsByCheckin = MQ_IsByCheckin,
			@mq_ImportType = MQ_ImportType
			From MIS_Quotas where MQ_Id = @mq_Id

	if (@mq_HotelKey is not null) set @mq_svkey = 3
	else begin
		set @mq_svkey = 1
		set @flightCityKeyFrom = (select top 1 CH_CitykeyFrom from Charter where CH_KEY = @mq_FlightKey)
	end

    -- Если Commitment
	IF(@mq_QuotaType = 0)
	BEGIN
		SET @qdtype = 2
	END
	-- Если Allotments --
	ELSE
	BEGIN
		SET @qdtype = 1
	END
	-- mq_ImportType 0-наличие мест, 1-квоты
    BEGIN TRY
        IF (@mq_Places >= 0)
        BEGIN
            IF (NOT EXISTS (SELECT TOP 1 1
                            FROM Quotas WITH(NOLOCK)
                            INNER JOIN QuotaObjects WITH(NOLOCK) ON QT_ID = QO_QTID
                            WHERE QT_PRKey = @mq_PartnerKey
                                AND QO_SVKey = @mq_svkey
                                AND QO_Code = isnull(@mq_HotelKey, @mq_FlightKey)
                                AND QO_SubCode1 = isnull(@mq_RoomKey, @mq_AirServiceKey)
                                AND QO_SubCode2 = isnull(@mq_RoomCategoryKey, @flightCityKeyFrom)
                                AND ((@mq_HotelKey is not null and QT_ByRoom = 1) or (@mq_FlightKey is not null and QT_ByRoom = 0))
                                AND QT_IsByCheckIn = 0))
            BEGIN
				if(@mq_ImportType = 0 OR (@mq_ImportType = 1 AND @mq_Places > 0))
				BEGIN
					INSERT INTO Quotas (QT_PRKey, QT_ByRoom, QT_Comment, QT_IsByCheckIn)
					VALUES (@mq_PartnerKey, (case isnull(@mq_HotelKey,0) when 0 then 0 else 1 end), '', 0)
					SET @qtid = SCOPE_IDENTITY()

					INSERT INTO QuotaObjects (QO_QTID, QO_SVKey, QO_Code, QO_SubCode1, QO_SubCode2)
					VALUES (@qtid, @mq_svkey, isnull(@mq_HotelKey, @mq_FlightKey), isnull(@mq_RoomKey, @mq_AirServiceKey), isnull(@mq_RoomCategoryKey, @flightCityKeyFrom))
					SET @qoid = SCOPE_IDENTITY()

					INSERT INTO QuotaDetails (QD_QTID, QD_Date, QD_Type, QD_Release, QD_Places, QD_Busy, QD_CreateDate, QD_CreatorKey)
					VALUES (@qtid, @mq_Date, @qdtype, NULLIF(@mq_Release, 0), @mq_Places, 0, GETDATE(), ISNULL(@uskey,0))
					SET @qdid = SCOPE_IDENTITY()

					UPDATE MIS_Quotas SET MQ_MTKey = @qdid, UpdateDate = GETDATE() WHERE MQ_Id = @mq_Id

					INSERT INTO QuotaParts (QP_QDID, QP_Date, QP_Places, QP_Busy, QP_IsNotCheckIn, QP_Durations, QP_CreateDate, QP_CreatorKey, QP_Limit)
					VALUES (@qdid, @mq_Date, @mq_Places, 0, 0, '', GETDATE(), ISNULL(@uskey,0), 0)

					UPDATE QuotaObjects
					SET QO_CTKey = (SELECT HD_CTKey FROM HotelDictionary WITH(NOLOCK) WHERE HD_Key = QO_Code)
					WHERE QO_SVKey = @mq_svkey AND QO_ID = @qoid AND QO_CTKey IS NULL

					UPDATE QuotaObjects
					SET QO_CNKey = (SELECT CT_CNKey FROM CityDictionary WITH(NOLOCK) WHERE CT_Key = QO_CTKey)
					WHERE QO_CNKey IS NULL AND QO_CTKey IS NOT NULL AND QO_ID = @qoid

					UPDATE MIS_Quotas SET MQ_ErrorState = NULL WHERE MQ_Id = @mq_Id
                END
            END
            ELSE
            BEGIN
                IF EXISTS (SELECT TOP 1 1
                        FROM Quotas WITH(NOLOCK)
                        INNER JOIN QuotaDetails WITH(NOLOCK) ON QT_ID = QD_QTID
                        INNER JOIN QuotaObjects WITH(NOLOCK) ON QT_ID = QO_QTID
                        WHERE QT_PRKey = @mq_PartnerKey
                            AND QO_SVKey = @mq_svkey
                            AND QO_Code = isnull(@mq_HotelKey, @mq_FlightKey)
                            AND QO_SubCode1 = isnull(@mq_RoomKey, @mq_AirServiceKey)
                            AND QO_SubCode2 = isnull(@mq_RoomCategoryKey, @flightCityKeyFrom)
                            AND QD_Date = @mq_Date
                            AND ((@mq_HotelKey is not null and QT_ByRoom = 1) or (@mq_FlightKey is not null and QT_ByRoom = 0))
                            AND QD_Type = @qdtype
                            AND QT_IsByCheckIn = 0)
                BEGIN
					select @qdid = qd.QD_ID, @qdbusy = qd.QD_Busy from 
						(select QO_QTID from QuotaObjects WITH(NOLOCK) where 
							QO_SVKey = @mq_svkey 
						AND QO_Code = isnull(@mq_HotelKey, @mq_FlightKey)
						AND QO_SubCode1 = isnull(@mq_RoomKey, @mq_AirServiceKey) 
						AND QO_SubCode2 = isnull(@mq_RoomCategoryKey, @flightCityKeyFrom)) as qo
							join (select QT_ID from Quotas WITH(NOLOCK) where
								QT_PRKey = @mq_PartnerKey 
							AND QT_IsByCheckIn = 0 
							AND ((@mq_HotelKey is not null and QT_ByRoom = 1) or (@mq_FlightKey is not null and QT_ByRoom = 0)))
								as qt on qt.QT_ID = QO_QTID
							join (select QD_ID,QD_Busy,QD_QTID from QuotaDetails WITH(NOLOCK) where 
								 QD_Date = @mq_Date 
							 AND QD_Type = @qdtype) 
								as qd on qt.QT_ID = qd.QD_QTID

                    IF (@mq_ImportType = 1 AND @qdbusy > @mq_Places)
                    BEGIN
                         -- Число занятых мест в МТ больше числа мест пришедших
						PRINT 'Число занятых мест в МТ больше числа мест пришедших'
						if @isMT11 = 1 begin
							UPDATE QuotaDetails SET QD_Places = @mq_Places, QD_Release = NULLIF(@mq_Release, 0), QD_IsDeleted = NULL WHERE QD_ID = @qdid
							UPDATE QuotaParts   SET QP_Places = @mq_Places, QP_IsDeleted = NULL WHERE QP_QDID = @qdid
						end else begin
							UPDATE QuotaDetails SET QD_Places = QD_Busy, QD_Release = NULLIF(@mq_Release, 0), QD_IsDeleted = NULL WHERE QD_ID = @qdid
							UPDATE QuotaParts   SET QP_Places = QP_Busy, QP_IsDeleted = NULL WHERE QP_QDID = @qdid
						end
                        UPDATE MIS_Quotas SET MQ_ErrorState = 1 WHERE MQ_Id = @mq_Id AND MQ_ErrorState IS NULL
                    END
                    ELSE
					IF (@mq_ImportType = 0 AND @qdbusy > @mq_Places)
					BEGIN
					    UPDATE QuotaDetails SET QD_Places = @mq_Places, QD_Busy = @mq_Places, QD_Release = NULLIF(@mq_Release, 0), QD_IsDeleted = NULL WHERE QD_ID = @qdid
                        UPDATE QuotaParts   SET QP_Places = @mq_Places, QP_Busy = @mq_Places, QP_IsDeleted = NULL WHERE QP_QDID = @qdid
                        UPDATE MIS_Quotas   SET MQ_ErrorState = 1 WHERE MQ_Id = @mq_Id AND MQ_ErrorState IS NULL
					END
                    ELSE
					IF (@mq_ImportType = 0 AND @mq_Places = 0)
					BEGIN
					    UPDATE QuotaDetails SET QD_Places = 0, QD_Busy = 0, QD_Release = NULLIF(@mq_Release, 0), QD_IsDeleted = 4 WHERE QD_ID = @qdid
                        UPDATE QuotaParts   SET QP_Places = 0, QP_Busy = 0, QP_IsDeleted = 4 WHERE QP_QDID = @qdid
                        UPDATE MIS_Quotas   SET MQ_ErrorState = 1 WHERE MQ_Id = @mq_Id AND MQ_ErrorState IS NULL
					END
					ELSE
                    BEGIN
                        -- пришел 0 и в МТ занятых мест 0 - удаляем квоту
                        IF (@mq_ImportType = 1 AND @mq_Places = 0 AND @qdbusy = 0)
                        BEGIN
                            PRINT 'пришел 0 и в МТ занятых мест 0 - удаляем квоту'
                            UPDATE QuotaDetails
                            SET QD_IsDeleted = 4 -- Request
                            WHERE QD_ID = @qdid
                            UPDATE MIS_Quotas SET MQ_MTKey = @qdid, UpdateDate = GETDATE() WHERE MQ_Id = @mq_Id
                            UPDATE MIS_Quotas SET MQ_ErrorState = NULL WHERE MQ_Id = @mq_Id
                        END
                        ELSE
                        BEGIN
                            UPDATE QuotaDetails SET QD_Places = @mq_Places, QD_Release = NULLIF(@mq_Release, 0), QD_IsDeleted = NULL WHERE QD_ID = @qdid
                            UPDATE QuotaParts SET QP_Places = @mq_Places, QP_IsDeleted = NULL WHERE QP_QDID = @qdid
                            UPDATE MIS_Quotas SET MQ_MTKey = @qdid, UpdateDate = GETDATE(), MQ_ErrorState = NULL WHERE MQ_Id = @mq_Id
                        END
                    END
                END
                ELSE
                BEGIN
                    IF (@mq_ImportType = 0 OR (@mq_ImportType = 1 AND @mq_Places > 0))
                    BEGIN
                    SELECT TOP 1 @qtid = QT_ID, @qoid = QO_ID
                        FROM Quotas WITH(NOLOCK)
                        INNER JOIN QuotaObjects WITH(NOLOCK) ON QT_ID = QO_QTID
                        WHERE QT_PRKey = @mq_PartnerKey
                            AND QO_SVKey = @mq_svkey
                            AND QO_Code = isnull(@mq_HotelKey, @mq_FlightKey)
                            AND QO_SubCode1 = isnull(@mq_RoomKey, @mq_AirServiceKey)
                            AND QO_SubCode2 = isnull(@mq_RoomCategoryKey, @flightCityKeyFrom)
                            AND ((@mq_HotelKey is not null and QT_ByRoom = 1) or (@mq_FlightKey is not null and QT_ByRoom = 0))
                            AND QT_IsByCheckIn = 0
                        ORDER BY QT_ID

                        INSERT INTO QuotaDetails (QD_QTID, QD_Date, QD_Type, QD_Release, QD_Places, QD_Busy, QD_CreateDate, QD_CreatorKey)
                        VALUES (@qtid, @mq_Date, @qdtype, NULLIF(@mq_Release, 0), @mq_Places, 0, GETDATE(), ISNULL(@uskey,0))

                        SET @qdid = SCOPE_IDENTITY()

                        UPDATE MIS_Quotas SET MQ_MTKey = @qdid, UpdateDate = GETDATE(), MQ_ErrorState = NULL WHERE MQ_Id = @mq_Id

                        INSERT INTO QuotaParts (QP_QDID, QP_Date, QP_Places, QP_Busy, QP_IsNotCheckIn, QP_Durations, QP_CreateDate, QP_CreatorKey, QP_Limit)
                        VALUES (@qdid, @mq_Date, @mq_Places, 0, 0, '', GETDATE(), ISNULL(@uskey,0), 0)
                    END
                END
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @errorMessage2 AS NVARCHAR(MAX)
        IF(@qdtype = 2)
        BEGIN
			SET @errorMessage2 = 'Error in LoadMisQuotas commitment: ' + ERROR_MESSAGE() + CONVERT(NVARCHAR(MAX), @mq_Id)
		END
		ELSE
		BEGIN
			SET @errorMessage2 = 'Error in LoadMisQuotas allotment: ' + ERROR_MESSAGE() + CONVERT(NVARCHAR(MAX), @mq_Id)
		END
        INSERT INTO SystemLog (sl_date, sl_message) VALUES (GETDATE(), @errorMessage2)
    END CATCH

	-- импорт квот
	IF @mq_ImportType = 1
	BEGIN
		-- рассадка в квоты по раннее оформленным услугам, т.е. cажаем в квоты услуги, которые сидят на запросе
		IF EXISTS (SELECT TOP 1 1
					FROM Dogovorlist WITH(NOLOCK)
					JOIN HotelRooms WITH(NOLOCK) ON DL_SUBCODE1 = HR_KEY
					WHERE dl_svkey = @mq_svkey
						AND dl_code = isnull(@mq_HotelKey, @mq_FlightKey)
						AND ((isnull(@mq_RoomCategoryKey, @flightCityKeyFrom) = 0) OR (HR_RCKEY = isnull(@mq_RoomCategoryKey, @flightCityKeyFrom)))
						AND (SELECT COALESCE(MIN(SD_State), 4) FROM ServiceByDate WHERE SD_DLKey = DL_Key) = 4
						AND @mq_Date BETWEEN DL_DateBeg AND DL_DATEEND)
		BEGIN
			-- Вставляем в таблицу для посадки услуг на квоту
			insert into ProtourServiceToQuota (PQ_HotelKey, PQ_SubCode2, PQ_Date) values (isnull(@mq_HotelKey, @mq_FlightKey), isnull(@mq_RoomCategoryKey, @flightCityKeyFrom), @mq_Date)
		END
    END
END
GO

GRANT EXEC ON [dbo].[ImportMisQuota] TO PUBLIC
GO
