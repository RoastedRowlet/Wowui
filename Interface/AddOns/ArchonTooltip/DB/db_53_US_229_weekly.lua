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

local lookup = {'DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Monk-Windwalker','Paladin-Retribution','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','Druid-Restoration','Druid-Balance',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaralyn:BAAANQADCgIIAgAAAA==.',
Ab='Abmikaze:BAAANQADCggICQAAAA==.Abysseon:BAAANQAECgQICQAAAA==.',
Ac='Ace:BAAANQAECgQIBwAAAA==.',
Ad='Adios:BAACNQAFFIEHAAIBAAQJ8wjbAwA6AQABAAQJ8wjbAwA6AQA1AAQKgRoAAgEACQlvHPwJAP0CAAEACQlvHPwJAP0CAAAA.Adorean:BAAANQAECgUIBgAAAA==.',
Ag='Age:BAAANQAECgQIBAAAAA==.Agrohn:BAAANQADCgIIAgAAAA==.',
Ai='Aimnskin:BAAANQADCgcIEAAAAA==.',
Al='Alcore:BAAANQAECgEIAQAAAA==.Aliine:BAAANQAECgMIAwAAAA==.',
Am='Ameiisaa:BAAANQAECgEIAQAAAA==.Amethaendron:BAAANQADCgYIBwAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAABNQAECoEdAAICAAkJsBv1FADUAgACAAkJsBv1FADUAgAAAA==.',
An='Anxie:BAAANQAECgcIBwAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAUIBgADABoXAA==.',
Ao='Aoifae:BAAANQAECgEIAQAAAA==.',
Ap='Apickle:BAAANQADCgUIBQAAAA==.Applecider:BAAANQAECgcIDwAAAA==.Apprentice:BAAANQAECgEIAQAAAA==.',
Ar='Aramos:BAAANQAECgUICgAAAA==.Aramôs:BAAANQADCggIEwAAAA==.Arkhangel:BAAANQAECgMIBQAAAA==.Arta:BAAANQADCggIGAAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAAANQAECgIIAwAAAA==.',
At='Atraxx:BAAANQABCgIIAgAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQADCgUIBgAAAA==.',
Be='Beaker:BAAANQAECgUIBwAAAA==.Beastmode:BAAANQAECgUICwAAAA==.Bedlem:BAAANQADCggIGgAAAA==.Beko:BAAANQAECgIIAwAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQABCgIIAgAAAA==.',
Bi='Bidoof:BAAANQAECgMIBAAAAA==.Billydan:BAAANQAECgQIBQAAAA==.',
Bl='Blackhide:BAAANQABCgMIBAAAAA==.Blackpanthxr:BAAANQAECgYIDAAAAA==.Blackvortex:BAAANQADCgIIAgAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECggIEQAEAAAAAA==.Bloodyburst:BAAANQAECgcIEwABNQAECggIEQAEAAAAAA==.Bloodyfistz:BAAANQAECggIEQAAAA==.Blue:BAAANQAECgMICQAAAA==.Bluethreetwo:BAAANQAECgIIAgAAAA==.',
Bo='Bookofzeref:BAAANQADCgEIAQAAAA==.',
Br='Brayend:BAAANQAECgMIAwAAAA==.Brimscythe:BAAANQAECgYIDwAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggICgAAAA==.Caliandis:BAAANQAECgIIAgAAAA==.Calvey:BAAANQAECgMIAwAAAA==.Cambrai:BAAANQADCggIGwAAAA==.Cannabelle:BAAANQAECgUIDwAAAA==.Carclias:BAABNQAECoEZAAMFAAgJuRb8DAD+AQAFAAcJzhb8DAD+AQAGAAYJrROITQCUAQAAAA==.Carthrix:BAAANQADCggIEgAAAA==.Catbarf:BAAANQADCggIBgABNQAECggIDgAEAAAAAA==.Cathrix:BAAANQADCgIIAgAAAA==.Cattlerage:BAAANQAECgIIAgAAAA==.',
Ce='Cellika:BAAANQAECgEIAQAAAA==.Cerdelz:BAAANQAECgMIAwAAAA==.',
Ch='Chaoscookies:BAAANQAECgYIDwAAAA==.Chartkov:BAAANQADCgcICgAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECggIGAAHAD4PAA==.',
Ci='Cinderpetal:BAAANQAECgEIAQAAAA==.',
Ck='Ckay:BAAANQADCggICAAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAAANQAECgcIDgABNQAECgkJGAAGAK8eAA==.Comlock:BAAANQADCgQIBQAAAA==.Complacent:BAAANQAECgMIBAAAAA==.Comspyder:BAAANQADCgYICgAAAA==.Coriander:BAAANQAECgYICwAAAA==.Corii:BAAANQADCgMIAwAAAA==.Cosmo:BAAANQAECgEIAQABNQAECgMIBQAEAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggICQABNQAFFAUICAAIAC4XAA==.',
Cy='Cyonicus:BAAANQAECgUIBgAAAA==.Cyska:BAAANQAECgYIDwAAAA==.',
['Cé']='Cécé:BAAANQAECgQICgAAAA==.',
['Cë']='Cëcë:BAAANQADCgMIBgAAAA==.',
Da='Dababayaga:BAAANQADCgYICAAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAAANQAECgYICgAAAA==.Dagevas:BAAANQADCgYIBgAAAA==.Dakeria:BAAANQADCgYICgAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYICQAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEANQAECgYICwABNQAECggIFAAJAFIgAA==.Dax:BAAANQAECgEIAQAAAA==.Daxing:BAAANQADCggIFAABNQAECgYICwAEAAAAAA==.',
De='Deeppurple:BAAANQADCgcICQAAAA==.Del:BAAANQAECgUICgAAAA==.Demoraliziñg:BAAANQADCggIDgAAAA==.Demostache:BAABNQAECoEYAAMGAAkJrx7cFAC7AgAGAAgJxR3cFAC7AgAFAAEJACYtSABwAAAAAA==.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgEIAQAAAA==.',
Dh='Dhargal:BAAANQAECgUICgAAAA==.',
Dk='Dkfaros:BAAANQADCgYICwABNQAECgUIBwAEAAAAAA==.',
Do='Dolomite:BAAANQAECgQIBQAAAA==.Dorow:BAAANQAECgYIDwAAAA==.Dotabolt:BAAANQAECgQICAAAAA==.',
Dr='Dracthyris:BAAANQADCgYIBgAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgcIEAAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAAANQAECggIDgAAAA==.',
Du='Dunsel:BAAANQADCggIFgABNQAECgYIDwAEAAAAAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQADCggIDgAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAAANQAECgUICQAAAA==.',
['Dã']='Dãnny:BAAANQADCgEIAQABNQAECgUICQAEAAAAAA==.',
Eb='Ebonshade:BAAANQADCgUIDAAAAA==.',
Ed='Edena:BAAANQADCgEIAQAAAA==.Edginglord:BAAANQADCggIDQAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQABNQADCgUIBQAEAAAAAA==.Eloras:BAAANQAECgEIAQAAAA==.Elunbi:BAAANQAECgcIEgAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQADCgEIAQAAAA==.',
Ep='Epsilòn:BAEANQAECggIDAAAAA==.',
Er='Ernest:BAAANQADCgcIFgAAAA==.Errani:BAAANQAECgIIAwAAAA==.',
Es='Esper:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAAANQAECgEIAQAAAA==.',
Ev='Evilkarma:BAAANQADCggIGwAAAA==.Evocatis:BAAANQAECgcIEwAAAA==.',
Ey='Eyesdeadeyed:BAAANQAECgYIEQAAAA==.',
Fa='Faion:BAAANQAECgQIBQAAAA==.Faon:BAAANQADCgEIAQAAAA==.Farrea:BAAANQADCggIDQAAAA==.Fayvia:BAAANQABCggIDQAAAA==.',
Fe='Feebz:BAAANQADCgEIAQAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgUICwAAAA==.',
Fi='Firebirdz:BAAANQAECgcIDAAAAA==.',
Fl='Flygon:BAAANQAECgEIAQAAAA==.',
Fo='Forque:BAAANQADCgYICAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAAANQAECgQICAAAAA==.Frizby:BAAANQAECgEIAQAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgEIAgAAAA==.',
Fy='Fyrelord:BAAANQADCggIGgAAAA==.Fyuna:BAAANQAECgUICgAAAA==.',
Ga='Gark:BAAANQADCgcIEAAAAA==.Garkk:BAAANQADCgQIBAAAAA==.Gazzi:BAAANQAECgYICwAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.',
Gi='Gióvanna:BAAANQADCgUICAAAAA==.',
Gl='Glodskegg:BAAANQAECgYICwAAAA==.',
Go='Goyim:BAAANQADCggIDQAAAA==.',
Gr='Gr:BAAANQADCgMIBwAAAA==.Grissoul:BAAANQABCgQIBAAAAA==.Grody:BAAANQAECgIIAgAAAA==.',
Gu='Guroo:BAAANQAECgUICgAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
Ha='Hagarn:BAAANQAECgYIDgAAAA==.Halimah:BAAANQAECgQICAAAAA==.Halois:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.Hardtwosee:BAAANQAECggIDQABNQAFFAIIAQAEAAAAAA==.Harleypaw:BAAANQADCggICAAAAA==.Hazan:BAAANQAECgYIBgABNQAECggIDgAEAAAAAA==.',
He='Hexmachine:BAAANQAECgYIDgAAAA==.',
Ho='Hole:BAAANQADCgYIBgAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQADCgcICQAAAA==.',
Hy='Hypertext:BAAANQADCgYIDwAAAA==.',
Ia='Iamahriman:BAAANQAECgIIAwAAAA==.',
Ig='Ignite:BAAANQAECgYIDgAAAA==.',
Il='Illestria:BAAANQAECgUICQAAAA==.Illumiscotty:BAAANQAECgYIDwAAAA==.',
In='Incognonetoo:BAAANQAECgYIBAAAAA==.Insania:BAAANQAECgEIAQAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgQICwAAAA==.',
Ja='Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQADCgYIBgABNQAECgYICwAEAAAAAA==.Jastirri:BAAANQAECgUIBgAAAA==.',
Ji='Jimothy:BAAANQADCgYIBgABNQABCgQIAgAEAAAAAA==.',
Jo='Johneringo:BAAANQADCgYICwAAAA==.Jonjee:BAAANQAECgYICwAAAA==.',
Ju='Juicez:BAAANQADCggIDgAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECgcIBAAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECgQIBgAAAA==.Katio:BAAANQAECgYIDwAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAAANQADCggIFgAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQADCgcIFAAAAA==.Kessandra:BAACNQAFFIEGAAMGAAQJKx57BQAZAQAGAAMJlBx7BQAZAQAKAAEJ8CLYAQBnAAA1AAQKgRkAAwoACQlGJGYAAGgDAAoACQn7ImYAAGgDAAYAAwn1G+yEAOMAAAAA.Kexally:BAAANQADCgcIFgAAAA==.Kexkan:BAAANQADCgQIBAABNQADCgcIFgAEAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAAANQAECgYICwAAAA==.',
Ki='Kiarah:BAAANQAECgEIAgAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAAANQAECgIIAgAAAA==.Kisor:BAAANQADCgEIAQAAAA==.Kitchenstink:BAAANQAECgYICwAAAA==.',
Ko='Koifo:BAAANQABCgQIBAAAAA==.',
Kp='Kplaow:BAAANQABCggICgAAAA==.',
Kr='Kritanta:BAAANQAECgUICgAAAA==.Krystallus:BAAANQADCgUIBQAAAA==.',
Ku='Kurnea:BAAANQADCggIEwAAAA==.',
La='Lachlann:BAAANQADCggIGgAAAA==.Lakartó:BAABNQAECoEZAAQLAAgJiRfXCQBiAgALAAgJiRfXCQBiAgAMAAEJWB8gLgBaAAANAAEJTw6/EwA3AAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgMIAwAAAA==.',
Ld='Ldritch:BAABNQAECoEZAAMOAAkJtiCkDQBUAgAOAAYJgSOkDQBUAgAPAAUJjB2yFwDMAQAAAA==.',
Le='Leifson:BAAANQAECgIIAwAAAA==.Leonedis:BAAANQAECgEIAQAAAA==.Lethea:BAAANQADCgYICAAAAA==.Levious:BAAANQAECgMIAwAAAA==.',
Li='Lianara:BAAANQADCgQIBAABNQADCgcIEAAEAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lu='Ludo:BAAANQAECgcIEwAAAA==.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAAANQAECgUICgAAAA==.Luxurious:BAAANQAECgIIAgAAAA==.',
Ma='Maaca:BAAANQADCgYICgAAAA==.Malachor:BAAANQADCgQIBAABNQADCggIDwAEAAAAAA==.Maligned:BAAANQAECgEIAQAAAA==.Martichoux:BAAANQAECgYICwAAAA==.Match:BAAANQAECgIIAgAAAA==.Mathas:BAAANQAECgYIDwAAAA==.Mathilda:BAAANQADCgYIBgAAAA==.',
Mc='Mccholock:BAAANQAECgEIAgAAAA==.Mcmach:BAAANQAECgIIAgAAAA==.',
Me='Mehaoloka:BAAANQADCgcICgAAAA==.Memelle:BAAANQAECgIIAgAAAA==.Menoah:BAAANQAECgMIAwAAAA==.Merdoc:BAAANQAECgQIBAAAAA==.Meredith:BAAANQAECgIIAgAAAA==.Mesilana:BAAANQADCggIDAAAAA==.Metrx:BAAANQADCgUIBQAAAA==.',
Mi='Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAAANQAECgIIAgAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgIIAgAAAA==.Monichan:BAAANQADCgcICAAAAA==.Moosecheeks:BAAANQAECgUIBQAAAA==.Morganna:BAAANQABCgUIBwAAAA==.Morior:BAAANQADCggIEQAAAA==.Morslucifer:BAAANQAECgUICQAAAA==.Motorcade:BAAANQAECgEIAQAAAA==.',
Mu='Mutent:BAAANQADCgYIDAAAAA==.',
My='Mypal:BAAANQADCggIGwAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
Na='Naula:BAAANQADCgUICgAAAA==.',
Ne='Neather:BAAANQAECgIIAgAAAA==.Neron:BAAANQADCgQIBAAAAA==.Nezkima:BAAANQADCgQIBAAAAA==.',
Ni='Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAAANQADCggIEQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAgAAAA==.Nira:BAAANQAECgUICAAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAAANQAECgEIAQAAAA==.',
No='Nodöts:BAAANQAECggICAABNQAFFAIIAQAEAAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQAECgEIAQAAAA==.Notron:BAAANQAECgQIBgAAAA==.Noz:BAAANQADCgYICgAAAA==.',
Ny='Nychophysis:BAAANQAECgIIAgAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Om='Omars:BAAANQAECgEIAQAAAA==.',
On='Ontherun:BAAANQADCgYICQAAAA==.',
Op='Oprawinfury:BAAANQADCgcIEAAAAA==.',
Ou='Ourus:BAAANQAECgcIEgAAAA==.',
Pa='Pallaminnow:BAAANQADCggIGwAAAA==.Paulo:BAAANQAECgMIBgAAAA==.',
Pe='Pele:BAAANQADCgcIEAAAAA==.Perpetrator:BAAANQAECgIIAgAAAA==.',
Pi='Piki:BAAANQAECgMIBAAAAA==.',
Po='Poepwn:BAAANQAECgQIBQAAAA==.',
Pu='Puffypanda:BAAANQADCgcIDAAAAA==.',
Qu='Quill:BAAANQAECgYICwAAAA==.',
Ra='Raging:BAAANQADCgUIBQABNQAECgQIBwAEAAAAAA==.Ralz:BAAANQAECgQICQAAAA==.Rangon:BAAANQADCggICAAAAA==.Rannick:BAAANQAECgMIAwAAAA==.Ranua:BAAANQADCgUICQABNQAECgYICwAEAAAAAA==.Ratdemonmike:BAAANQAECgEIAgAAAA==.Ratio:BAAANQAECggIDQAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgMIAwAAAA==.',
Ru='Ruden:BAAANQADCggIDwAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECgYIBgABNQAECggIDgAEAAAAAA==.',
Rw='Rwqr:BAAANQAECgQICgAAAA==.',
Sa='Salacakei:BAAANQAECgQICAAAAA==.Salin:BAAANQAECgMIAwAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFIEGAAIQAAQJSRxbAQB4AQAQAAQJSRxbAQB4AQA1AAQKgRoAAhAACQmLJV8BAJ0DABAACQmLJV8BAJ0DAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scoobie:BAAANQADCgQIBQABNQAECgQIBwAEAAAAAA==.Scoobydo:BAAANQABCgIIAgABNQAECgQIBwAEAAAAAA==.Scratches:BAAANQABCgIIAgAAAA==.Scrubs:BAAANQAFFAEIAQAAAA==.',
Se='Seider:BAAANQADCggICAAAAA==.Septemberr:BAAANQADCgQIBAAAAA==.',
Sh='Shadpriest:BAAANQABCgIIAgAAAA==.Shaggzy:BAACNQAFFIEIAAIIAAUJLhe1AQC/AQAIAAUJLhe1AQC/AQA1AAQKgSIAAggACQmjIwoCAJwDAAgACQmjIwoCAJwDAAAA.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAAANQAECgMIAwAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAAANQAECgEIAgAAAA==.Shockdoctor:BAAANQAECgQIBwAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJHQARAO0gAA==.',
Sl='Sleples:BAAANQAECgQIBwAAAA==.Slufgor:BAAANQADCgYIDwAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCgYICwAAAA==.',
Sn='Snoo:BAAANQAECgEIAQAAAA==.',
So='Solarlite:BAAANQADCgEIAQAAAA==.Solinari:BAAANQABCgIIAgAAAA==.Sophix:BAAANQADCgcICgAAAA==.Sorovar:BAAANQAECgYICwAAAA==.Soulbreakër:BAAANQAECgQICQAAAA==.',
Sp='Specimen:BAAANQADCgYICgAAAA==.Speddling:BAAANQAECgMIBQAAAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQADCgYIFAAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.',
St='Starbrow:BAAANQAECgUIBwAAAA==.Stormlight:BAAANQADCgYIEQAAAA==.Strudelmaker:BAAANQAECgIIAgAAAA==.',
Su='Summernight:BAAANQABCgIIAgAAAA==.Sushistryke:BAAANQADCggIEgAAAA==.',
Sy='Syland:BAAANQAECgEIAgAAAA==.Sylvanäs:BAAANQADCgYIDAAAAA==.Sysna:BAAANQAECgQIDQAAAA==.',
['Sä']='Sämi:BAAANQADCgYIBgABNQADCgcIEgAEAAAAAA==.',
Ta='Talley:BAAANQAECgUICwAAAA==.Tankwar:BAAANQADCgUIDQAAAA==.Targis:BAAANQAECgUICgAAAA==.Tazanaz:BAAANQADCgQIBAABNQAECgYICwAEAAAAAA==.',
Te='Templeton:BAAANQADCgMIAwAAAA==.',
Th='Thaleas:BAAANQADCgEIAQAAAA==.Thegreatkhal:BAAANQADCggIGwAAAA==.Thorizine:BAAANQAECgYICgAAAA==.Thorlas:BAAANQAECgIIBAAAAA==.',
Ti='Timmúk:BAAANQAECgQICwAAAA==.',
To='Tolkorthuul:BAAANQAECgEIAQABNQADCgcICAAEAAAAAA==.Tomma:BAAANQAECgYICwAAAA==.Torsion:BAAANQADCggICAAAAA==.',
Tr='Trailerpark:BAAANQABCgQIBwAAAA==.Tratre:BAAANQAECgMIAwAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQADCggIGAAAAA==.',
Tu='Tumboflakes:BAAANQADCggICAABNQAFFAQIBgASABkZAA==.Tust:BAAANQADCggIDgABNQABCgQIAgAEAAAAAA==.',
Ty='Tylandy:BAAANQAECgUIBwAAAA==.Tytaniormu:BAAANQAECgQIBQAAAA==.',
['Tê']='Tês:BAAANQAECgIIBAAAAA==.',
Un='Undeadbetty:BAAANQADCgUIBQAAAA==.',
Va='Vaayl:BAAANQAECgIIAwAAAA==.Vaelraen:BAAANQAECgEIAQAAAA==.Valcher:BAAANQADCgYICwAAAA==.Valendera:BAAANQAECgYICwAAAA==.Valifadin:BAAANQAECgIIAgAAAA==.Valndrevy:BAAANQADCgYICwAAAA==.Vansan:BAAANQAECgYICwAAAA==.',
Ve='Venngennce:BAAANQAECgYIDwAAAA==.',
Vi='Viktir:BAAANQADCgQIBAABNQADCgcIEAAEAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Vorkath:BAAANQAECgUICgAAAA==.Vormette:BAAANQADCgYICwAAAA==.',
Vt='Vtae:BAAANQADCggIGAAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAAANQAECgQIBQAAAA==.',
Wo='Woxkal:BAAANQAECgMIAwAAAA==.',
Wu='Wubblebubble:BAAANQAECgMIBAAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgEIAgAAAA==.',
Xu='Xuzhu:BAAANQADCgYICAAAAA==.',
Yl='Ylvis:BAAANQAECgQIBQAAAA==.',
Yo='Yol:BAAANQAECgcIDwAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECgQIBwAAAQ==.',
Za='Zarion:BAABNQAECoEXAAMTAAgJpSO2AwA3AwATAAgJpSO2AwA3AwAUAAEJ2wWPeQAjAAAAAA==.Zarra:BAAANQAECgIIBAAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBAAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQADCgUIBQABNQAECggIFwATAKUjAA==.Ziyar:BAAANQAECgEIAQABNQAECggIFwATAKUjAA==.',
Zo='Zocorro:BAAANQADCgcIEAAAAA==.',
Zy='Zypherdius:BAAANQADCgYIBgAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAABNQAECoEaAAIJAAkJTyGADwAnAwAJAAkJTyGADwAnAwAAAA==.',
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
