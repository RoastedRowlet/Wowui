local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Paladin-Holy','Druid-Guardian','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Mage-Frost','Mage-Fire','Druid-Feral','DeathKnight-Blood','Shaman-Enhancement','Evoker-Preservation','Priest-Holy','Warrior-Arms','Hunter-Survival','Shaman-Elemental','Hunter-Marksmanship','Paladin-Retribution','Druid-Restoration',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaphrodite:BAAANQADCgMIAwAAAA==.',
Ab='Abyssalblink:BAACNQAFFH8aAAMBAAcKThbuAgBgAgABAAcKThbuAgBgAgACAAMKARA5DgC9AAA1AAQKfx8AAwIACQr6HmcdAGQCAAIACQr1G2cdAGQCAAEAAgoEI25tAL0AAAAA.',
Ah='Ahruud:BAAANQADCgMIAwAAAA==.',
Ak='Akeno:BAAANQADCgIIAgABNQAECggIDwADAAAAAA==.',
Al='Albie:BAABNQAECn8jAAIEAAkK1BOkkABeAgAEAAkK1BOkkABeAgAAAA==.Albtraum:BAAANQADCgMIAwAAAA==.Aleight:BAABNQAECn8YAAIFAAgKow0GhQD+AQAFAAgKow0GhQD+AQAAAA==.Alice:BAAANQADCgIIAgAAAA==.Alius:BAAANQADCggIDwAAAA==.',
Am='Ambellina:BAABNQAECn8qAAIGAAkKDhzgIgDeAgAGAAkKDhzgIgDeAgAAAA==.',
Ba='Bambiietta:BAAANQAECgQIBgAAAA==.',
Be='Belanwolf:BAAANQADCgIIAgAAAA==.',
Bl='Blastoiz:BAAANQADCgYIBgAAAA==.',
Bu='Bulvar:BAAANQADCgIIAgAAAA==.',
Ca='Caligos:BAAANQADCgQIBAAAAA==.Capriestson:BAAANQADCggICAAAAA==.Cardrin:BAABNQAECn8gAAIHAAkKpBfdDwBdAgAHAAkKpBfdDwBdAgAAAA==.',
Ce='Cerbulum:BAAANQADCgMIAwAAAA==.',
Ch='Chat:BAAANQADCgMIAwAAAA==.Choplo:BAACNQAFFH8bAAIIAAcKUx5GAgBjAgAIAAcKUx5GAgBjAgA1AAQKfxoAAggACQotIHUZAHMCAAgACQotIHUZAHMCAAAA.Chudmuffin:BAAANQAECgcIDwAAAA==.',
Ci='Cinema:BAAANQAFFAEIAgAAAA==.',
Cl='Clarence:BAAANQADCgIIAgAAAA==.',
Co='Cobalt:BAEANQAECgMJAwABNQAFFAUIBQAJAMQPAA==.',
Cr='Creativename:BAAANQABCgUIBQAAAA==.Crona:BAAANQADCgIIAgAAAA==.',
Da='Daemon:BAABNQAECn8aAAQKAAkKBh+ECAB0AgAKAAkKkhmECAB0AgAJAAUKYSDYsABpAQALAAEKVx+mKgBBAAAAAA==.Dalast:BAAANQAECgEIAQAAAA==.',
De='Debockulus:BAABNQAECn83AAMJAAkKaxd4QQCKAgAJAAkKaxd4QQCKAgAKAAUKfQVQPgDIAAAAAA==.Decentychi:BAAANQAECggIDgAAAA==.Dedia:BAAANQAECgEIAQAAAA==.Derangedxo:BAACNQAFFH8UAAQJAAgKhB0fBwD7AQAJAAYKQCAfBwD7AQALAAEKkheUBwBkAAAKAAEKhBiiGwBPAAA1AAQKfx4AAwoACQqtJSIJAGcCAAoABwrvICIJAGcCAAkABgplJQZjACwCAAAA.',
Do='Doggie:BAAANQADCgMIAwAAAA==.',
Dr='Dreambreath:BAAANQAECgMIBQAAAA==.Drunkenhoe:BAAANQAECgYIEgAAAA==.',
Ea='Earthwalkin:BAAANQADCgMIAwAAAA==.',
Ed='Edger:BAAANQADCgMIAwAAAA==.',
El='Elcomer:BAAANQADCgIIAgAAAA==.',
En='Enana:BAABNQAECn8WAAIMAAgKMQkDjABnAQAMAAgKMQkDjABnAQAAAA==.Enkor:BAAANQAECgYICAAAAA==.',
Er='Era:BAAANQAECgYIEwABNQADCgMIAwADAAAAAA==.',
Ev='Everblack:BAABNQAECn8qAAQKAAkKih07BwCSAgAKAAcKvB47BwCSAgAJAAcKqQ8pjQDBAQALAAMKSiFnGADFAAAAAA==.Evilcretin:BAABNQAECn9sAAQEAAkKGyaMAQD1AwAEAAkKGyaMAQD1AwANAAIKsCPLIgDSAAAOAAEKgyHxCQBiAAAAAA==.',
Fa='Faraah:BAABNQAECn8/AAIPAAkKKCXlAADYAwAPAAkKKCXlAADYAwAAAA==.',
Ga='Ganondorf:BAABNQAECn8eAAIQAAgKjxXMRgDbAQAQAAgKjxXMRgDbAQAAAA==.Gatecrashr:BAAANQAECgIIAgAAAA==.',
Gi='Gimlï:BAAANQADCgYICgAAAA==.',
Gl='Gluttony:BAAANQAECgQIBAABNQAECgkJGgARANwRAA==.',
Gn='Gnosis:BAAANQADCggIFgAAAA==.',
Go='Goch:BAAANQAECgYIEwAAAA==.Goldenwind:BAAANQAECggIBAAAAA==.Goodluck:BAAANQADCgMIAwABNQAFFAUIDgASAL8ZAA==.',
Gp='Gp:BAAANQAECgEIAQAAAA==.',
Gr='Grimdark:BAABNQAECn8fAAIMAAcKJxaWbgC8AQAMAAcKJxaWbgC8AQAAAA==.Grunge:BAAANQAFFAIIAgAAAA==.',
Ha='Haven:BAAANQAECgEIAQAAAA==.',
He='Heathermarie:BAABNQAECn8rAAIOAAgKSiTRAAAnAwAOAAgKSiTRAAAnAwAAAA==.',
Hi='Hinata:BAAANQAECgEIAQAAAA==.',
Ho='Holdmyhammer:BAAANQADCgMIAwAAAA==.Holypride:BAAANQADCgUIBQABNQAECgkJGgARANwRAA==.Hotbut:BAABNQAECn8fAAITAAkK4RsRIgDkAgATAAkK4RsRIgDkAgAAAA==.',
['Hø']='Hørus:BAAANQADCgcIBwAAAA==.',
Ia='Iaptopz:BAAANQADCgcIDQAAAA==.',
Ir='Irishbaby:BAAANQAECgEJAgAAAA==.',
Iz='Iza:BAABNQAECn8iAAIMAAgKIw13dACqAQAMAAgKIw13dACqAQAAAA==.',
Ja='Jake:BAEANQAECgMIBgAAAA==.',
Je='Jeisansan:BAAANQAECgYIBgAAAA==.',
Ju='Juri:BAAANQAFFAEIAQAAAA==.',
Ka='Kallivor:BAAANQAECgcIDQAAAA==.Kanbu:BAAANQADCgEIAQAAAA==.Kardd:BAAANQAECgUIEQAAAA==.',
Ke='Keltic:BAAANQAECggIDQAAAA==.',
Kh='Khantyer:BAAANQADCgYIAwAAAA==.',
Ki='Kigafan:BAAANQAECgYIBgAAAA==.Kiing:BAAANQADCgUIBQAAAA==.',
Kr='Krowlhy:BAAANQAECgIIAgAAAA==.',
La='Laezel:BAABNQAECn8fAAIUAAgKHxz8bQBFAgAUAAgKHxz8bQBFAgAAAA==.Lamppost:BAABNQAECn8eAAIVAAkKYiVIAADbAwAVAAkKYiVIAADbAwAAAA==.Landliebe:BAAANQADCggILwAAAA==.Lannister:BAAANQADCgUIBQABNQAECggIIgASACUUAA==.',
Le='Lereios:BAAANQAECgYIDgABNQAECggIEQADAAAAAA==.Lessons:BAAANQADCgEIAQAAAA==.',
Li='Lightsmith:BAAANQAECgQIBQAAAA==.Lilpump:BAAANQAECgYIBwABNQAECggIDwADAAAAAA==.Lith:BAACNQAFFH8KAAIBAAQKERWCDQAvAQABAAQKERWCDQAvAQA1AAQKfyYAAwEACQoWI+YLAEoDAAEACQoWI+YLAEoDAAIAAQoAAOpyACUAAAAA.Liyun:BAAANQAECgIIAgAAAA==.',
['Lø']='Løry:BAAANQAFFAEIAgABNQAFFAUICgAGAGERAA==.',
Ma='Mahyor:BAABNQAECn8dAAMMAAgKTxQiXgDxAQAMAAgKTxQiXgDxAQAWAAYK1xrIgQCcAQAAAA==.Maroonfive:BAAANQAECgUIBQABNQAFFAUIBwAWAFMJAA==.Maybringer:BAAANQADCgQIBAAAAA==.Mazzh:BAACNQAFFH8RAAMXAAYK8B8WBgDzAQAXAAYK4BcWBgDzAQAFAAEKECfTOwBAAAA1AAQKfx0AAxcACQrIH1UbAHcCABcACQpEGlUbAHcCAAUABgqXDlHsACMBAAE1AAUUCQk7AAQA7CUA.',
Mu='Murmurr:BAAANQAECgEIAQAAAA==.',
Na='Naric:BAAANQAECggIEQAAAA==.Narium:BAAANQADCggIHQAAAA==.Nasa:BAAANQAECgMIAwAAAA==.',
No='Nobru:BAAANQAECgQIBQAAAA==.Now:BAABNQAECn8iAAMWAAkK/he1QABvAgAWAAkK/he1QABvAgAMAAEKIwSGLQEfAAAAAA==.',
Nu='Nukenin:BAABNQAECn8lAAICAAkK9CRlBACOAwACAAkK9CRlBACOAwAAAA==.Nunquam:BAAANQADCgUIBQAAAA==.',
Ny='Nyrasha:BAACNQAFFH8FAAIFAAQKEhLoEgAvAQAFAAQKEhLoEgAvAQA1AAQKfykAAgUACQrEIaobACgDAAUACQrEIaobACgDAAAA.',
Pa='Paredes:BAAANQAECgQIAwAAAA==.',
Pe='Peonu:BAAANQAECgYIEwAAAA==.',
Po='Police:BAABNQAECn8nAAMMAAkKRR+BFQAhAwAMAAkKRR+BFQAhAwAWAAUK6hchhQCTAQAAAA==.',
Pr='Pride:BAABNQAECn8aAAIRAAkK3BHcDQCNAgARAAkK3BHcDQCNAgAAAA==.Proteus:BAAANQAECgYICgAAAA==.Prounion:BAAANQADCgYIBgABNQAECgUIBwADAAAAAA==.',
Pu='Puff:BAABNQAECn8YAAIEAAcKiRDP7gCpAQAEAAcKiRDP7gCpAQAAAA==.',
Ra='Rana:BAAANQAECgYICgAAAA==.Ratko:BAAANQADCggIDwAAAA==.',
Re='Rekk:BAAANQAECggICAAAAA==.Reventön:BAAANQADCgcIBgAAAA==.Rey:BAAANQAECgUIDgAAAA==.',
Ro='Rockandstone:BAAANQAECggIDwAAAA==.',
Ru='Rubyredyoshi:BAAANQAECgYIBgAAAA==.Runtzsr:BAAANQABCgQIBQAAAA==.',
['Rá']='Ráîstlin:BAABNQAECn8hAAMNAAkKABI2EQCQAQAEAAgKXQkb6AC2AQANAAYK6BU2EQCQAQAAAA==.',
Se='Selro:BAAANQAECgUIBgAAAA==.',
Sh='Shadøw:BAAANQAECgQIBQAAAA==.Shinoa:BAAANQAECgEIAQAAAA==.Shockzzer:BAAANQADCgMIAwAAAA==.',
So='Soulszaura:BAAANQAECgQIBAAAAA==.',
St='Starchucker:BAACNQAFFH8NAAICAAUKnRp9BwCQAQACAAUKnRp9BwCQAQA1AAQKfzYAAgIACQpII6AGAGcDAAIACQpII6AGAGcDAAAA.',
Sw='Swade:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.Sweetnwicked:BAAANQAECgYIEgAAAA==.',
Sy='Synarri:BAABNQAECn8YAAMYAAkK8hPrjQAFAgAYAAgK8hTrjQAFAgAGAAcKdRaCXAAAAgABNQAFFAcIGwAGAPUbAA==.Syneria:BAACNQAFFH8bAAMGAAcK9Rs6AQC3AgAGAAcK9Rs6AQC3AgAYAAEKkxWDMwBCAAA1AAQKf7cAAwYACQqxJWsAAPUDAAYACQqxJWsAAPUDABgACQpFI6gVAG0DAAAA.Syneriah:BAAANQAECgEIAQABNQAFFAcIGwAGAPUbAA==.Synn:BAAANQADCggICAABNQAFFAcIGwAGAPUbAA==.Synnamon:BAABNQAECn80AAMYAAkKbyZEAgDtAwAYAAkKbyZEAgDtAwAGAAUK6gn1sAAZAQABNQAFFAcIGwAGAPUbAA==.Synpai:BAACNQAFFH8NAAMGAAYKjww3CQDJAQAGAAYKjww3CQDJAQAYAAEKUgsiNgA9AAA1AAQKf0YAAxgACQoNIX4WAGkDABgACQoNIX4WAGkDAAYABgpJHrpbAAICAAE1AAUUBwgbAAYA9RsA.',
Ta='Taciitus:BAABNQAECn8pAAIIAAkKWx2WFQCiAgAIAAkKWx2WFQCiAgAAAA==.Tailzz:BAAANQAECgUIEwAAAA==.',
Th='Thebaptiser:BAAANQADCgUIBQAAAA==.Thunderwar:BAAANQADCgIIAgAAAA==.',
Ti='Tiazy:BAAANQADCgYICAAAAA==.',
To='Toomato:BAAANQAECgQIBAAAAA==.Totemterror:BAEBNQAECn8YAAIMAAkKVCV+AwCwAwAMAAkKVCV+AwCwAwAAAA==.Tough:BAAANQADCgQIBAAAAA==.',
Ty='Tydraduel:BAACNQAFFH8FAAIJAAIKlg2nMACYAAAJAAIKlg2nMACYAAA1AAQKfykAAgkACQoLHYgjAPMCAAkACQoLHYgjAPMCAAAA.',
Tz='Tzuruchanise:BAAANQADCgMIBAAAAA==.',
Va='Vala:BAAANQAECgEIAQABNQAECggIIgASACUUAA==.Valy:BAAANQAECgUIDAAAAA==.Vannathyfall:BAAANQADCgUIDAAAAA==.Vany:BAAANQAECgEIAQAAAA==.',
Vo='Vora:BAAANQAECgYIDQAAAA==.',
Vw='Vw:BAAANQAECgIIAgAAAA==.',
Wh='Whalethen:BAEANQAECgcICAABNQAECgkJGAAMAFQlAA==.Wheresdebeef:BAAANQADCggIBAABNQAECgUIBwADAAAAAA==.',
Wi='Wikkid:BAAANQADCgUJBwAAAA==.Wikkidsin:BAAANQADCgUICAABNQADCgUJBwADAAAAAA==.',
['Wù']='Wùlph:BAAANQAECgQIBAAAAA==.',
Xx='Xxz:BAAANQADCgUIBwAAAA==.',
Yi='Yiesus:BAAANQAECggIDwABNQAFFAcIGgACALImAA==.',
Yo='Yomato:BAABNQAECn8xAAIZAAkKCB1rDQD1AgAZAAkKCB1rDQD1AgAAAA==.',
Yu='Yuanti:BAAANQADCgIIAgAAAA==.',
Za='Zabble:BAAANQABCgMIAwAAAA==.',
Ze='Zenocline:BAABNQAECn8fAAIIAAgKRBgqIQAeAgAIAAgKRBgqIQAeAgAAAA==.',
Zi='Zi:BAAANQAECggIDwAAAA==.',
['Ån']='Åntisocial:BAAANQAECgUIBwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
