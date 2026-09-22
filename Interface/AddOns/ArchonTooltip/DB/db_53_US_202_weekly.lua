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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Druid-Feral','Mage-Frost','Mage-Arcane','Shaman-Elemental','Priest-Holy','Shaman-Enhancement','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Rogue-Subtlety','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Rogue-Assassination','Druid-Balance','Priest-Shadow','Paladin-Protection','Warrior-Arms','Priest-Discipline','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQADCggJCAABNQAECgkJHwABAOkiAA==.',
Ad='Admaris:BAABNQAECoEfAAMCAAkKqh9WBQAyAwACAAkKqh9WBQAyAwADAAIKwhYfGwCVAAAAAA==.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFIEPAAMEAAYKXxUhAgCvAAAFAAQKCxPZDwBhAQAEAAIKBxohAgCvAAA1AAQKgRsAAwUACQpDIiMtAAgDAAUACQpDIiMtAAgDAAQAAQpCGHgtAD0AAAAA.',
Al='Alnasham:BAABNQAECoEiAAIGAAkKlx8AEAAzAwAGAAkKlx8AEAAzAwAAAA==.Alnava:BAAANQAECgUJCQAAAA==.Alvoka:BAAANQAECgYJEQAAAA==.',
Am='Amarillos:BAAANQAECgYIBgAAAA==.Amarillys:BAABNQAECoEWAAIHAAkKpRp6IQCFAgAHAAkKpRp6IQCFAgAAAA==.Ammutseba:BAAANQAECgUIDgAAAA==.',
An='Anfall:BAABNQAECoEeAAIIAAkKoBsrBQAEAwAIAAkKoBsrBQAEAwAAAA==.Angermeier:BAAANQAECgcIEgAAAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggJAwAAAA==.Anthos:BAAANQAECgUJBQAAAA==.Antikreist:BAAANQADCgQJBAAAAA==.',
Ap='Aphotic:BAAANQABCgYJBgAAAA==.',
Ar='Ards:BAAANQADCgEIAQAAAA==.Armanite:BAAANQAECgIJAgABNQAECggIDwAJAAAAAA==.Arthaniis:BAAANQAECgYJEwAAAA==.',
As='Asystoli:BAAANQAECgEIAQAAAA==.',
At='Atheria:BAAANQADCgYIBgAAAA==.',
Au='Audideath:BAAANQADCggIGQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Aw='Aw:BAACNQAFFIEJAAIKAAUKoRzmAgC9AQAKAAUKoRzmAgC9AQA1AAQKgR8AAgoACQrwJY4BANEDAAoACQrwJY4BANEDAAAA.',
Ax='Ax:BAEBNQAECoEdAAIBAAkKiB9ODQAbAwABAAkKiB9ODQAbAwAAAA==.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgQIBAAAAA==.',
Ba='Bamph:BAAANQAECgYJCwAAAA==.Bangbang:BAAANQAECgYICQAAAA==.Batez:BAAANQAECgQIBAABNQAFFAQJBwALAHALAA==.',
Bd='Bdk:BAAANQAECgUJBQAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgYICQAAAA==.Beledros:BAABNQAECoEcAAIMAAkKVBMNDgB5AgAMAAkKVBMNDgB5AgAAAA==.Beni:BAABNQAECoEmAAMNAAkKJiBMAgBQAwANAAkKJiBMAgBQAwADAAMKhwghGwCVAAAAAA==.Benson:BAABNQAECoEhAAIOAAkKoB0SBADrAgAOAAkKoB0SBADrAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFIEVAAMPAAYKByCNAABgAgAPAAYKByCNAABgAgAQAAIKygFFCwCNAAA1AAQKgRwABA8ACQoYJu8XANgCAA8ABwoZJu8XANgCABAABwpLGLcOAPEBABEAAQpHIPEbAEsAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgQJBAAAAA==.Brewtherguy:BAAANQAECgcJEwAAAA==.Bruceshepard:BAAANQADCgQIBwABNQAECgIIAgAJAAAAAA==.Brutebuffalo:BAAANQAECgcJEwAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgYJDAAAAA==.',
['Bâ']='Bâra:BAAANQAECgcIEQAAAA==.',
Ca='Carnal:BAAANQADCgUJBQAAAA==.',
Ce='Cedren:BAABNQAECoEiAAMKAAkKTRqTEQC6AgAKAAkKbBmTEQC6AgASAAgKARYGGwAtAgAAAA==.Ceewhya:BAAANQADCgQIBAAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQADCgYICAAAAA==.Chama:BAAANQAECgYIEQAAAA==.Cheapheal:BAABNQAECoEbAAINAAgKgh+cBADQAgANAAgKgh+cBADQAgAAAA==.Cheburashka:BAABNQAECoEZAAIGAAkKxh43GgDaAgAGAAkKxh43GgDaAgAAAA==.Chimerabob:BAAANQAECgIIAwAAAA==.Chunkymonkey:BAACNQAFFIEHAAITAAQKTRVBBABFAQATAAQKTRVBBABFAQA1AAQKgSMAAhMACQprINMIAAADABMACQprINMIAAADAAAA.',
Ci='Cidren:BAAANQAECgEJAQAAAA==.',
Cl='Clappncheeks:BAAANQAECgQIBQAAAA==.Claudefrollo:BAAANQADCggIFgAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAAANQAECgUIDQAAAA==.Crimsonaxel:BAAANQAECgUJCgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAJAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAAANQAECgUICwAAAA==.Dam:BAAANQADCgUIBQABNQAECgcJEgAJAAAAAA==.Dangerruss:BAAANQAECgQJCAAAAA==.Dashytash:BAAANQAECgUIDgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQADCgcJCAAAAA==.',
De='Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECoEjAAMQAAkKYB02CQBKAgAPAAgKsRqnLABuAgAQAAcKzR02CQBKAgAAAA==.Denagorn:BAABNQAECoEeAAIUAAkKACTCCQCJAwAUAAkKACTCCQCJAwABNQAFFAUIDQABAFURAA==.Dentsama:BAAANQADCgEJAQAAAA==.Deplete:BAAANQADCgIJAgABNQAECgcICwAJAAAAAA==.Deutzfr:BAABNQAECoEYAAIVAAkKlRyuAgDeAgAVAAkKlRyuAgDeAgAAAA==.Develop:BAAANQAECgMIAwAAAA==.Devos:BAAANQAECgYIEAABNQAECggIHgAGAGsaAA==.',
Do='Dominant:BAAANQAECgcJEAAAAA==.',
Dp='Dpssos:BAAANQAECgYICgAAAA==.',
Dr='Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAAANQAECgYIDAAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgIIAwAAAA==.Drygth:BAAANQADCgMJBQABNQAECggIFwAWAMkcAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAABNQAECoEYAAIXAAkKRxxFFAC/AgAXAAkKRxxFFAC/AgAAAA==.',
Du='Dushimaya:BAABNQAECoEeAAIYAAkKMSC7CQBJAwAYAAkKMSC7CQBJAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgYIDAAJAAAAAA==.',
Dw='Dwyndi:BAAANQAECgYJBgAAAA==.',
Ei='Eisador:BAAANQAECgYICwAAAA==.',
El='Elsen:BAAANQAECgQJCQAAAA==.Elsha:BAABNQAECoEXAAIOAAgKfRoXBwBqAgAOAAgKfRoXBwBqAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgUJBQAAAA==.',
Ev='Evelira:BAAANQAFFAIIAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezpzndaheezy:BAAANQADCgYIBgABNQAECgcJEgAJAAAAAA==.',
Fa='Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFIEFAAIYAAMKYAJ+DADRAAAYAAMKYAJ+DADRAAA1AAQKgSIAAhgACQr5Fe4mAHACABgACQr5Fe4mAHACAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAABNQAECoEcAAMZAAkKKR/xGQDeAgAZAAkKKR/xGQDeAgAaAAQKSg8ROgDbAAAAAA==.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAAANQAECgUJDAAAAA==.Fleebly:BAABNQAECoEWAAISAAgK7xT5FwBSAgASAAgK7xT5FwBSAgAAAA==.',
Fn='Fndruid:BAAANQAECgIJAgAAAA==.',
Fo='Fourbees:BAAANQAECgcIEQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECggJHgAbADQXAA==.',
Gi='Gilgamesh:BAAANQAECgYJCwAAAA==.',
Go='Gorobob:BAAANQAECgIIAwAAAA==.',
Gr='Graygkl:BAAANQAECgUJCgAAAA==.Greshanwise:BAAANQAECgMIAwAAAA==.Grimreaper:BAAANQAECgcJEwAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAABNQAECoEXAAMWAAgKyRzCCQCyAgAWAAgKsxvCCQCyAgAcAAcKAhptGQAiAgAAAA==.',
Ha='Haarp:BAAANQAECgMJBAAAAA==.Hakü:BAAANQAECgEIAQAAAA==.Hammered:BAAANQAECgQJAwAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heifer:BAABNQAECoEhAAIdAAkKVyByDgAiAwAdAAkKVyByDgAiAwABNQAFFAEJAQAJAAAAAA==.Hemophilia:BAAANQAECgYIDgAAAA==.Heydk:BAAANQAECgYJEAAAAA==.Heydruid:BAAANQADCgcJCAABNQAECgYJEAAJAAAAAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAAANQAECgUICwABNQAECgYIEAAJAAAAAA==.Hottsauce:BAABNQAECoEVAAIIAAkK0hW7BwC0AgAIAAkK0hW7BwC0AgAAAA==.Hottsaucefel:BAAANQAECgYJBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQADCgYIDAAAAA==.Hushhides:BAAANQAECgYJBgAAAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAAANQAECgEIAQABNQAECgcJDwAJAAAAAA==.Iblisshaytan:BAABNQAECoEcAAIKAAkKnxFHGwBKAgAKAAkKnxFHGwBKAgABNQAECgkJGwAWAOsTAA==.Ibtrollin:BAAANQADCgcJHgAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Io='Ionissa:BAAANQAECgcICgAAAA==.',
Is='Ischia:BAABNQAECoEkAAMHAAkKxBdnIgCAAgAHAAkKxBdnIgCAAgAeAAEK6gfEWwAmAAAAAA==.',
Ja='Jarl:BAAANQADCgYICQAAAA==.',
Jc='Jch:BAACNQAFFIELAAIZAAUKxRebAgC5AQAZAAUKxRebAgC5AQA1AAQKgSMAAxkACQrSJCsGAIcDABkACQrSJCsGAIcDABoAAQpkFu1VAEIAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAABNQAECoEaAAITAAkKuB5UCgDhAgATAAkKuB5UCgDhAgAAAA==.Jedikepjr:BAAANQAECgcJBwABNQAECgkJGgATALgeAA==.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAAANQAECgYIDQAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQADCggIFAAAAA==.',
Jp='Jprottsoo:BAABNQAECoEZAAIdAAgKmx0VFgDMAgAdAAgKmx0VFgDMAgAAAA==.',
Ju='Jubei:BAAANQAECgYIDAAAAA==.',
Ka='Kalmya:BAAANQAECgcIEwAAAA==.Kalrath:BAAANQAECgIIAgABNQAECggIDwAJAAAAAA==.',
Ke='Keizzer:BAAANQAECgcJCwAAAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBAAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAAANQAECgcJDgAAAA==.',
Ko='Korris:BAAANQAECgcIEQAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAAANQAECgcJEwAAAA==.',
Ky='Kybinc:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAABNQAECoEeAAINAAkKvRO/CAA4AgANAAkKvRO/CAA4AgAAAA==.Lazyfrost:BAABNQAECoEWAAIFAAgKxw2EigD8AQAFAAgKxw2EigD8AQAAAA==.',
Le='Lethò:BAABNQAECoEYAAMYAAgKvx5JEgD5AgAYAAgKvx5JEgD5AgAUAAQKvBOGvgDoAAAAAA==.Lethô:BAAANQAECgEIAQAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAAANQAECgYIBgABNQAFFAQJBwALAHALAA==.Lilzarthe:BAAANQAECgQJDAAAAA==.',
Lo='Loerasdh:BAABNQAECoEaAAIKAAcKqyaiCQApAwAKAAcKqyaiCQApAwAAAA==.Loko:BAACNQAFFIELAAIdAAUKuxXwBAC5AQAdAAUKuxXwBAC5AQA1AAQKgR4AAh0ACQpEHowSAPICAB0ACQpEHowSAPICAAAA.Looio:BAAANQADCgMIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQABCgMIAwAAAA==.Luxxus:BAAANQAECgYJDQABNQAECgcJCwAJAAAAAA==.',
Ly='Lyesx:BAAANQAECgYICwABNQAFFAQJBwALAHALAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgEIAgAAAA==.Mageyousad:BAAANQADCgEIAQAAAA==.Maixia:BAAANQAECgIJBQAAAA==.Makhtor:BAAANQAECgMJBQAAAA==.Mallaer:BAABNQAECoEXAAIHAAgKYiJKEQD0AgAHAAgKYiJKEQD0AgAAAA==.Malícíous:BAAANQAECgYIEAAAAA==.Mantakore:BAABNQAECoEXAAIMAAcKnBfcFQDyAQAMAAcKnBfcFQDyAQAAAA==.Marcdruid:BAAANQAECgQJBwAAAA==.Maubles:BAAANQADCggJCAABNQAECggIGAAfAPMMAA==.',
Me='Menopaws:BAABNQAECoEWAAINAAgKOiO+AgA0AwANAAgKOiO+AgA0AwAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAAANQAECgcJEwAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAABNQAECoEnAAIWAAkKnCXPAADQAwAWAAkKnCXPAADQAwAAAA==.Milenko:BAAANQAECgYIDgAAAA==.Milly:BAAANQAECgMIBQABNQAECgYIDgAJAAAAAA==.',
Mo='Molfsongal:BAAANQADCgIJAgAAAA==.Monstrous:BAABNQAECoElAAIgAAkK5x70HAALAwAgAAkK5x70HAALAwAAAA==.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgQIBgAAAA==.Mothman:BAAANQAECgMJBAAAAA==.',
Ms='Msbehaven:BAAANQAECgUIDQAAAA==.',
Mu='Muffìns:BAAANQAECgIJAwAAAA==.Musashi:BAAANQAECgUICQAAAA==.',
My='Mynuturchin:BAAANQAECgUIBgAAAA==.',
Na='Nagy:BAAANQADCgcIDAAAAA==.',
Ni='Night:BAAANQAECgUICgAAAA==.Nightsecho:BAAANQABCgYIBgAAAA==.Nightshris:BAAANQAECgIIAgAAAA==.',
No='Notmehssos:BAAANQAECgYICgAAAA==.Notthechosen:BAAANQADCgMIBAABNQAECgQJBgAJAAAAAA==.',
Ny='Nymeriã:BAAANQAECgEJAQAAAA==.',
Ob='Obzy:BAAANQAECgYIDAAAAA==.Obzz:BAAANQADCgEIAQABNQAECgYIDAAJAAAAAA==.',
Ok='Okamy:BAAANQAECgYJCwAAAA==.',
Ol='Olympicjeid:BAAANQAECgQIBAABNQAECgkJGgATALgeAA==.',
Op='Opz:BAABNQAECoEbAAMeAAgKdRcxFQBPAgAeAAgKdRcxFQBPAgAhAAIKiBbmEgCNAAAAAA==.',
Pa='Parthos:BAAANQAECgMIBgAAAA==.',
Pe='Pedro:BAAANQADCgcIBwABNQADCggIEQAJAAAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgIIAgAAAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcJCwAAAA==.',
Pl='Ploxis:BAAANQAFFAIIAgAAAA==.',
Po='Polskashaman:BAAANQAECgQJCAAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgIIAwAJAAAAAA==.',
Pr='Prea:BAAANQAECgUJBQAAAA==.Premiumferal:BAABNQAECoEbAAMcAAkK8iBZCgDlAgAcAAkK8iBZCgDlAgAWAAUKFBm+JABUAQAAAA==.Primecarry:BAABNQAECoEbAAIYAAkKdSPhBACHAwAYAAkKdSPhBACHAwAAAA==.Prine:BAABNQAECoEVAAIgAAgKvBr6MgCcAgAgAAgKvBr6MgCcAgABNQAECgkJGwAYAHUjAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQABCgYIBgAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQABCgMIAwAAAA==.Raigko:BAABNQAECoEdAAIgAAkKrSEKFABAAwAgAAkKrSEKFABAAwAAAA==.Rainyday:BAAANQAECgUIDgAAAA==.Raiva:BAAANQAECgIIBAABNQAECgUIBgAJAAAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAJAAAAAA==.Rassputen:BAABNQAECoEjAAIXAAkKWREtLgDxAQAXAAkKWREtLgDxAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Relis:BAAANQABCgYICAAAAA==.Renais:BAAANQAECgMIAwAAAA==.Rex:BAAANQAECgcJEgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.',
Ro='Roguen:BAABNQAECoEbAAMWAAkK6xMgCwCXAgAWAAkK6xMgCwCXAgAcAAMKhgh+RwC5AAAAAA==.Romirin:BAAANQADCgQJBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAAANQAECgYIEAAAAA==.',
['Rù']='Rùckús:BAABNQAECoEZAAIBAAgK6xziFQC9AgABAAgK6xziFQC9AgAAAA==.',
Sa='Sacredmentos:BAAANQAECgYIEAAAAA==.Sammybeans:BAAANQADCgcJCAAAAA==.Sapito:BAAANQADCgYICgAAAA==.',
Se='Seceron:BAAANQAECgUJDAAAAA==.Sekai:BAAANQADCgcICQAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAAANQAECgcIEQAAAA==.Shatteredsky:BAABNQAECoEXAAMbAAgKqxtnKQBdAgAbAAgKqxtnKQBdAgAGAAEKqgPJ5QAuAAAAAA==.Shazik:BAABNQAECoEeAAIbAAgKNBc0MAA5AgAbAAgKNBc0MAA5AgAAAA==.Shazzik:BAAANQAECgYICgABNQAECggJHgAbADQXAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQADCgcJBwAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQAECgUIBgAAAA==.Sirjames:BAAANQADCggIDgAAAA==.',
Sk='Skelix:BAACNQAFFIEUAAIbAAYKAyLXAABzAgAbAAYKAyLXAABzAgA1AAQKgScAAhsACQpLJlIBAMYDABsACQpLJlIBAMYDAAAA.Skunkpaw:BAAANQADCgUIBgAAAA==.Skysong:BAABNQAECoEbAAMiAAkKJR78BwDFAgAiAAkKJR78BwDFAgAMAAMKfwUCOABEAAAAAA==.',
Sl='Slashedeye:BAABNQAECoEmAAIjAAYKdhNRAgC8AQAjAAYKdhNRAgC8AQAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowynn:BAAANQAECgYIDAAAAA==.Snubby:BAAANQAECgcJEwAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgMIAwAAAA==.Spicymeatbal:BAAANQABCggICwAAAA==.',
St='Strathz:BAAANQAECgcJEwAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Sunstrider:BAAANQADCgEIAQAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAQIBwATAE0VAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYJFQAPAAcgAA==.Sylätis:BAAANQAECgMJAwABNQAFFAYJFQAPAAcgAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAJAAAAAA==.',
Ta='Talys:BAACNQAFFIEMAAIMAAUKsBq0AwDKAQAMAAUKsBq0AwDKAQA1AAQKgSMAAgwACQrjHmUHAP4CAAwACQrjHmUHAP4CAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Texicola:BAABNQAECoEaAAIEAAgKghuvAwCOAgAEAAgKghuvAwCOAgAAAA==.',
Th='Thabdeady:BAAANQADCgcIBwABNQAECgcJEgAJAAAAAA==.Thabk:BAAANQAECgcJEgAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAAANQAECgQIBQAAAA==.Thurmond:BAAANQAECggIDwAAAA==.Thurmund:BAAANQADCgYIBgABNQAECggIDwAJAAAAAA==.',
Ti='Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQADCgcIFQAAAA==.Toastz:BAABNQAECoEZAAIZAAgKIh+MGwDVAgAZAAgKIh+MGwDVAgAAAA==.Toebeanz:BAAANQAECgQJDAAAAA==.Tokken:BAACNQAFFIEIAAIgAAQKHxSsCwA7AQAgAAQKHxSsCwA7AQA1AAQKgSMAAiAACQpVHzIgAPgCACAACQpVHzIgAPgCAAAA.',
Tr='Treebeast:BAAANQAFFAIIBAAAAA==.Troile:BAAANQADCgYIBwAAAA==.Trojen:BAAANQAECggIDQAAAA==.Trolladin:BAAANQADCgYICgABNQADCgcJHgAJAAAAAA==.',
Tw='Twig:BAAANQAECggJDQAAAA==.',
Ty='Tyras:BAAANQAECgIJAwAAAA==.',
['Tâ']='Tâz:BAABNQAECoEcAAIbAAgKZSCmFgDSAgAbAAgKZSCmFgDSAgAAAA==.',
Ul='Ulanda:BAAANQAECgYIDwAAAA==.',
Um='Umasi:BAACNQAFFIEMAAIfAAUKBiThAAAUAgAfAAUKBiThAAAUAgA1AAQKgSMAAh8ACQpUJn8AAOsDAB8ACQpUJn8AAOsDAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Ut='Utastebad:BAAANQADCgQIBAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAJAAAAAA==.Vail:BAAANQADCgMIBAAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQADCgUIBQAAAA==.',
Ve='Venandi:BAAANQAECgUICgAAAA==.Vengened:BAAANQAECgQJBgAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIDgAAAA==.',
Vi='Vilous:BAAANQAECgcJDwAAAA==.',
Vy='Vyisesham:BAAANQAECgUIDQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYIBgABNQADCgMIAwAJAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAAANQAECgcIEwAAAA==.Wez:BAAANQAECgEIAQAAAA==.',
Wh='Whiskee:BAAANQAECgYIDgAAAA==.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAAANQAFFAIIAgAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgQIBgAJAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQABCgYICgABNQAECgcJEAAJAAAAAA==.Xenophontes:BAAANQAECgcJEwABNQAFFAIIAgAJAAAAAA==.',
Xi='Xihuang:BAABNQAECoEYAAIdAAgKchMiKgAWAgAdAAgKchMiKgAWAgABNQAECgkJGwAWAOsTAA==.Xiia:BAAANQADCggICwAAAA==.',
Xo='Xouu:BAAANQAECggIAQABNQAECggIBQAJAAAAAA==.',
Xx='Xxuublue:BAAANQAECggIBQAAAA==.Xxuuspr:BAAANQAECggIAgABNQAECggIBQAJAAAAAA==.Xxuutwo:BAAANQAECggIAQABNQAECggIBQAJAAAAAA==.',
Ya='Yaoguai:BAAANQAECgcICwAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAAANQAECgQIBAABNQAECggIFwAOAH0aAA==.',
Za='Zaleris:BAAANQAECgQIBQAAAA==.',
Ze='Zephon:BAAANQAECgQJCQAAAA==.',
Zo='Zotiel:BAAANQADCgcIDwABNQAFFAUIDQABAFURAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAJAAAAAA==.',
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
