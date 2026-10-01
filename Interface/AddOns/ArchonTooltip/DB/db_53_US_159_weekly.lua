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

local lookup = {'Unknown-Unknown','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Shaman-Elemental','Warrior-Arms','Paladin-Protection','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Druid-Feral','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Priest-Shadow','Priest-Discipline','Priest-Holy','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','Monk-Brewmaster','Druid-Balance','Evoker-Preservation','Evoker-Devastation','DeathKnight-Frost','Monk-Windwalker','Monk-Mistweaver','Hunter-Survival','Paladin-Retribution','Evoker-Augmentation','Warrior-Protection','Warlock-Affliction','Shaman-Enhancement',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abris:BAAANQADCgUJBQABNQAECgEIAgABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECgcIDAAAAA==.Acidpriest:BAAANQAECgMIAwAAAA==.',
Ad='Adacey:BAAANQAECgUICQAAAA==.Adragon:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Adrenalized:BAAANQADCgIIAgAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgQICgAAAA==.',
Al='Alaunu:BAABNQAECoEcAAICAAgKnA6tFACTAQACAAgKnA6tFACTAQAAAA==.Alexx:BAAANQADCggJEAAAAA==.Alkaid:BAAANQAECgYIDAAAAA==.Alunariel:BAAANQADCgUIBQAAAA==.',
An='Anari:BAAANQAECgQJBwABNQAECggIDQABAAAAAA==.Anarky:BAAANQAECggICAAAAA==.Annebonny:BAAANQAECgMIAwAAAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECoEwAAMDAAgKsCHkEQDaAgADAAgKxh/kEQDaAgAEAAcKrRxKBgBfAgAAAA==.Arienys:BAAANQADCgYICwAAAA==.Arigosa:BAAANQADCgQIBwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQADCggICgAAAA==.Arleen:BAAANQADCgEIAQAAAA==.Arquen:BAAANQAECgYIDQAAAA==.Artemisia:BAAANQADCgYIDgAAAA==.',
As='Asheril:BAAANQADCgQICQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgUIBwAAAA==.Astrov:BAAANQAECgYIDQAAAA==.',
At='Atulmags:BAAANQAECgUICAAAAA==.',
Au='Auani:BAABNQAECoEhAAIFAAgKsSLvBwAYAwAFAAgKsSLvBwAYAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgIIAgAAAA==.',
Az='Azazyl:BAAANQADCgMIBgAAAA==.Azzeus:BAAANQAECgMIBgABNQAECggIFwAGAE4KAA==.Azzshot:BAABNQAECoEXAAMGAAgKTgqQNABKAQAHAAcKhAu0kACCAQAGAAgKWQOQNABKAQAAAA==.',
Ba='Babyrinsjr:BAAANQAECgIIAwAAAA==.Badista:BAAANQADCgIIAgAAAA==.Balleont:BAAANQAECgYIEwAAAA==.Barrada:BAAANQAECgUICwAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECoEkAAMIAAYK7AkyPgBMAQAIAAYK7AkyPgBMAQAJAAUKsgNOMgDsAAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAAANQAECgUICQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECoEhAAIHAAgK9B65IQDYAgAHAAgK9B65IQDYAgAAAA==.Bobbinrobin:BAAANQAECgQIBQABNQAECgUICQABAAAAAA==.Borahae:BAAANQAECgQICAABNQAECggIGQAKABoDAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQADCggIGgAAAA==.Breach:BAAANQAECgIIAwAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAAANQAECgEIAQAAAA==.Brünhilde:BAAANQAECgYIEgAAAA==.',
Bs='Bstbll:BAACNQAFFIEMAAIFAAUKFxMDBACYAQAFAAUKFxMDBACYAQA1AAQKgSYAAgUACQpnHeALANcCAAUACQpnHeALANcCAAAA.',
Bu='Bubbleheals:BAABNQAECoEVAAIKAAcKdQnQfgBKAQAKAAcKdQnQfgBKAQABNQAECgkJKQALAGAZAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgMIBQAAAA==.Buttsnacks:BAABNQAECoEXAAIMAAcK2xYEaQAKAgAMAAcK2xYEaQAKAgAAAA==.',
Ca='Caletha:BAAANQADCgYICwAAAA==.Callistrah:BAAANQAECgQIBgAAAA==.Caltaa:BAABNQAECoEhAAINAAgK8CHeBwDxAgANAAgK8CHeBwDxAgAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAOAJIZAA==.Canverian:BAAANQAECgIIAwAAAA==.Captsmash:BAAANQAECgUICwAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQABCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ch='Charcuterie:BAAANQAECgQJBwAAAA==.Chasseurfool:BAAANQAECgQIBQAAAA==.Chat:BAABNQAECoEmAAILAAkKfhtfJQC2AgALAAkKfhtfJQC2AgAAAA==.Chevre:BAAANQAECgQICwAAAA==.Chezaro:BAAANQAECgYIDwAAAA==.Chickenwing:BAAANQAECgYIEgAAAA==.Christano:BAAANQAECgYICQAAAA==.Christhecold:BAABNQAECoEXAAIMAAgKDhisWQA5AgAMAAgKDhisWQA5AgAAAA==.Chrollo:BAAANQAECgQICwAAAA==.Chumba:BAAANQAECgUICwAAAA==.',
Ci='Cinnamilk:BAAANQAECgMIAwABNQAECggIHwAPAAAZAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAQAF4hAA==.Cloudcrack:BAECNQAFFIEMAAMOAAQKAg/iCgA+AQAOAAQKAg/iCgA+AQALAAMKdArQEQDiAAA1AAQKgSMAAwsACQpsHWMcAPACAAsACQpsHWMcAPACAA4ACAqRHfErAHMCAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAAANQAECgUICwAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAAANQAECgcIEQABNQAECgYIEwABAAAAAA==.Cotw:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Coverttops:BAAANQAECgQIBAAAAA==.Cozytoby:BAAANQADCggIFQAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQADCggICAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUICgAAAA==.Cynri:BAAANQADCgQIBQABNQADCggIDwABAAAAAA==.Cyntrill:BAAANQADCggIIwAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgYIEwAAAA==.Dajoel:BAAANQADCggIFgAAAA==.Dalacia:BAAANQAECgYIDQAAAA==.Darknature:BAAANQAECgYIEwAAAA==.Darkodin:BAAANQAECgUICgAAAA==.Darkshamy:BAAANQADCggIDAAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAABNQAECoEtAAIMAAkKNB3aKgDkAgAMAAkKNB3aKgDkAgAAAA==.Dawinchy:BAABNQAECoEiAAMFAAgKxhnHFgBBAgAFAAgKxhnHFgBBAgARAAUK/RKFFAA8AQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggICAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAAANQAECgYICwAAAA==.Dellistia:BAAANQADCgYICwAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQADCgMIAwAAAA==.Desdamona:BAAANQAECgQIBAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAAANQAECgYIEAAAAA==.Devorick:BAABNQAECoEdAAMSAAgKhRWqRgA8AgASAAgKhRWqRgA8AgATAAIK9QNuXwBOAAAAAA==.',
Di='Diaval:BAAANQADCgYIDQAAAA==.Dijarl:BAAANQAECgcIBwAAAA==.Dipndots:BAAANQADCggIEAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Diyiya:BAAANQAECgUICwAAAA==.',
Do='Doorki:BAAANQADCggIDwAAAA==.Dottey:BAAANQAECgUIDQAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgIIAgAAAA==.Draickin:BAAANQAECgUIDwAAAA==.Drekle:BAAANQAECgMICAABNQAECgYIDwABAAAAAA==.Drelian:BAAANQADCggIGwAAAA==.Drevy:BAABNQAECoETAAIUAAcKVRmaBgA2AgAUAAcKVRmaBgA2AgAAAA==.Drewdox:BAAANQADCgUJDAAAAA==.Drewsguy:BAAANQADCgYIEwAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECggIFwAVALYLAA==.Drumk:BAAANQADCgIIAgABNQAECggIFwAVALYLAA==.Drumma:BAAANQADCgcIBwAAAA==.Drummer:BAABNQAECoEXAAQVAAgKtgvBLABtAQAVAAcKNgnBLABtAQAWAAUKrhSPDAA7AQAXAAQKWARjpgCsAAAAAA==.Drumroleplz:BAAANQADCggICAABNQAECggIFwAVALYLAA==.',
Dw='Dw:BAABNQAECoEWAAMYAAgK2hpIFACYAgAYAAgK2hpIFACYAgADAAMKqw/BWQCtAAABNQAECgkJGwAHANMhAA==.',
Ea='Earthsangel:BAAANQADCgYJCwAAAA==.',
Ec='Eclair:BAAANQAECgMIBQAAAA==.',
Ed='Edralyia:BAAANQADCgYICwAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgcIEgAAAA==.Einnarr:BAAANQADCggIFQAAAA==.',
El='Eldrinne:BAAANQAECgUIDAAAAA==.Eleblast:BAAANQAECgEJAQAAAA==.Elizavoid:BAAANQAECgYIEwAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAAANQAECgIIAwAAAA==.Elthiss:BAAANQAECgYIEwAAAA==.',
En='Enfer:BAAANQADCgUIBQABNQAECgkJJgALAH4bAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Erianthe:BAAANQAECgcIDwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQAECgQIBAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQADCgUIBQAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Fa='Faewhisker:BAAANQAECgYIBgAAAA==.Faithfool:BAAANQAECgcIEgAAAA==.Fancyfeet:BAAANQADCgcIBwABNQAECgkJFgAJAOgSAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAAANQAECgYIDwAAAA==.',
Fe='Fearios:BAABNQAECoEfAAIPAAgKABlhKgA2AgAPAAgKABlhKgA2AgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAAANQAECgEIAQAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAAANQAECgcIEAAAAA==.',
Fl='Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAABNQAECoEjAAMZAAgKoBi1ZwB+AgAZAAgKoBi1ZwB+AgAaAAEKVxmTLwBNAAAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAAANQAECgYIDgAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQAECgIIAgAAAA==.Garrotxa:BAAANQAECggICAABNQAECggIDQABAAAAAA==.',
Ge='Gevallen:BAAANQAECgUIBwAAAA==.',
Gh='Ghavinental:BAAANQAECgYIEAAAAA==.',
Gi='Gil:BAAANQAECgcIEAAAAA==.Gilgamesh:BAAANQAECgUIBQABNQAECgcIEAABAAAAAA==.',
Gl='Glizzard:BAAANQAECgUICgABNQAECgYIEAABAAAAAA==.Glocket:BAAANQAECgIJBAAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAAANQAECgUICwAAAA==.',
Go='Goatspace:BAAANQAECgYIEAAAAA==.Gongagà:BAABNQAECoEeAAIYAAcKsxA2JwDNAQAYAAcKsxA2JwDNAQAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQJCgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAAANQAECgUIEAAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAAANQAECgUIDwABNQAECgEIAQABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECoEhAAIbAAgKtiGgBAD0AgAbAAgKtiGgBAD0AgAAAA==.Hauwitzer:BAAANQADCgUIBQAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAAANQAECgcIDgAAAA==.',
He='Heartattack:BAAANQADCggICAAAAA==.Hecate:BAAANQAECgMIAwAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAAANQAECgQIBQAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQADCggIFgAAAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.',
Hu='Huunaron:BAAANQAECgYICwAAAA==.',
['Hé']='Héx:BAACNQAFFIETAAIZAAYKZxdNBgAdAgAZAAYKZxdNBgAdAgA1AAQKgRkAAhkACQpMGsxuAG0CABkACQpMGsxuAG0CAAAA.',
Id='Idylwilde:BAAANQAECgIIAgAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAAANQAECgUIDwAAAA==.',
Il='Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECgIIBAAAAA==.',
Io='Iobo:BAACNQAFFIEKAAIYAAUKLSMAAwD/AQAYAAUKLSMAAwD/AQA1AAQKgR8AAhgACQqpIwkFAHQDABgACQqpIwkFAHQDAAAA.',
Ir='Ironic:BAAANQADCgYIBgABNQAECggIIAAIAMYgAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAYICwAUALMVAA==.Jasseca:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQADCgYIDgAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaelkin:BAAANQAECgYIEwAAAA==.Kaelun:BAAANQADCgcICwABNQAECgYIEwABAAAAAA==.Kaelundrus:BAAANQAECgMIBgABNQAECgYIEwABAAAAAA==.Kainis:BAAANQADCggIIwAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgYICwAAAA==.Keilas:BAAANQAECgUIDQAAAA==.Kerron:BAAANQADCgYIFAAAAA==.Keylala:BAAANQAECgEIAQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Kickentail:BAAANQAECgQIBQAAAA==.Kiegh:BAAANQABCgQIBAAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAABNQAECoEnAAIMAAkKuyGpEwBUAwAMAAkKuyGpEwBUAwAAAA==.Kirlia:BAAANQAECgUIDgAAAA==.',
Kl='Klymax:BAAANQAECgEIAQAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECoEhAAIZAAkKbB9IIABEAwAZAAkKbB9IIABEAwAAAA==.Krobelus:BAAANQAECgcIDwAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQADCgMJAwAAAA==.Kyran:BAAANQADCggIDwAAAA==.',
['Kè']='Kèrónos:BAAANQAECgIIAgAAAA==.',
['Kì']='Kìllstheweak:BAAANQAECgYIDgAAAA==.',
La='Laeythe:BAEANQAECgQIBAABNQAECgkJIAAXAPskAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgIIAgAAAA==.',
Lc='Lclc:BAAANQAECgMIAwAAAA==.',
Le='Leafeon:BAAANQAECgEJAQABNQAFFAcIDwAOAA8ZAA==.Lebrin:BAAANQAECgQICwAAAA==.Legaia:BAABNQAECoEgAAIMAAgK+x/nMADLAgAMAAgK+x/nMADLAgAAAA==.Legendknewl:BAAANQADCgUIDAAAAA==.Leliel:BAAANQADCggICAABNQAECggIGgAKAMYaAA==.Lennyzamwam:BAAANQAECgQIBAAAAA==.Lesindre:BAAANQADCgcIDQABNQAECggIAQABAAAAAA==.Lexapro:BAAANQADCggIGQAAAA==.',
Li='Lianissa:BAAANQADCggIDwAAAA==.Lillinna:BAAANQAECgMIAwAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAAANQAECgYICAAAAA==.Lockycharmz:BAAANQAECgEIAQABNQAECggIHwAPAAAZAA==.Lorcán:BAAANQADCgYICwAAAA==.Lormazlezrax:BAABNQAECoEaAAIOAAkKkhn1LQBpAgAOAAkKkhn1LQBpAgAAAA==.',
Lu='Lucernyx:BAAANQADCggIFgAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Lunaera:BAAANQAECgQIBAAAAA==.Lune:BAAANQADCgcIBwABNQADCggIFAABAAAAAA==.Lunellia:BAAANQADCggIFAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECoETAAIMAAcK3hWafADQAQAMAAcK3hWafADQAQAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAAANQAECgMIBQAAAA==.Mageistmage:BAACNQAFFIEMAAIZAAUK2xbZDwCqAQAZAAUK2xbZDwCqAQA1AAQKgRYAAhkACQqBI2wxAA0DABkACQqBI2wxAA0DAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgUICwABAAAAAA==.Malegar:BAAANQADCgYIFAAAAA==.Malificent:BAAANQADCggIDgAAAA==.Mammajamma:BAABNQAECoEZAAIcAAcKWxLZPAC+AQAcAAcKWxLZPAC+AQAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECoEgAAIIAAgKoRbZHABBAgAIAAgKoRbZHABBAgAAAA==.Marwen:BAAANQADCgYICwAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECoEXAAIMAAgKyhA6dgDkAQAMAAgKyhA6dgDkAQAAAA==.',
Mc='Mcdeathy:BAAANQAECgUICgAAAA==.Mclardragos:BAABNQAECoEZAAMdAAkKXCElBABcAwAdAAkKXCElBABcAwAeAAEKUghdNQAwAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECoEgAAMIAAgKxiCOFgB6AgAIAAcK+h6OFgB6AgAJAAYKbh/tFwD6AQAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Megashamxl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgcICwAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECggIHgAXAB4VAA==.Meteion:BAAANQADCgMIAwABNQAECggIAQABAAAAAA==.',
Mi='Miacyn:BAAANQAECgIIBAAAAA==.Miladybast:BAAANQAECgQIBgAAAA==.Minke:BAAANQADCgcICAAAAA==.Mirra:BAAANQAECgYICwAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQAECgMIBQAAAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morionso:BAAANQAECgUIBwAAAA==.Morphyrinsjr:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.Mortarion:BAABNQAECoEfAAMQAAgKGhSqQwClAQAQAAcKexOqQwClAQAfAAcKvhBvNQCXAQAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggJFAAAAA==.',
Mu='Murdiûs:BAABNQAECoEZAAMgAAcKfB3WFQBUAgAgAAcKfB3WFQBUAgAhAAEKkRdJOwBEAAAAAA==.',
My='Mythbruh:BAEBNQAECoEfAAMQAAcKXiEfLwAZAgAQAAcKeCAfLwAZAgAfAAcKQhorJAAXAgAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECggIFwAVALYLAA==.Narl:BAAANQAECgIIBQAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgUIBwAAAA==.',
Ne='Necropally:BAAANQADCgcIDQAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAAANQAECgIIAwAAAA==.Noraelara:BAAANQAECggIAQAAAA==.Norezfou:BAABNQAECoEhAAMVAAgK1BosGwAmAgAVAAcKYBosGwAmAgAXAAgK0RTvUADZAQAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAAANQAECgcIEQAAAA==.',
Od='Odanobunaga:BAABNQAECoEgAAIMAAgK0RvwTwBaAgAMAAgK0RvwTwBaAgAAAA==.Odyn:BAAANQAECgMIAwAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECoEaAAIQAAcKLB6CJgBSAgAQAAcKLB6CJgBSAgABNQAECggIIgAiAEEjAA==.Oripal:BAAANQADCgcICAABNQAECggIIgAiAEEjAA==.Oríon:BAABNQAECoEiAAQiAAgKQSNjAwCWAgAiAAcKICNjAwCWAgAGAAYKJxa6KwCZAQAHAAQKARxanQBjAQAAAA==.',
Pa='Pankratease:BAAANQAECgUIBwAAAA==.Pankratoes:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Papahess:BAAANQAECgUIDwAAAA==.Paradias:BAABNQAECoEWAAIJAAkK6BIOFAAmAgAJAAkK6BIOFAAmAgAAAA==.Pastor:BAAANQABCgIIAgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQAECgIIAwAAAA==.Petespally:BAAANQAECgEIAgAAAA==.',
Pf='Pfftpfft:BAAANQAECgIIAgAAAA==.',
Ph='Pha:BAAANQAECgcIDwAAAA==.Phatdanny:BAAANQAECgYIBwAAAA==.Phonycheese:BAABNQAECoEZAAIjAAcKfBlQaQAGAgAjAAcKfBlQaQAGAgAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAEBNQAECoElAAISAAkKlRiBKgCkAgASAAkKlRiBKgCkAgAAAA==.',
Po='Pocalypse:BAAANQAECgEIAQAAAA==.Ponkeyfists:BAABNQAECoEeAAIgAAkKIiJ1BABzAwAgAAkKIiJ1BABzAwAAAA==.Portstar:BAABNQAECoEWAAIZAAgKywZM0ACUAQAZAAgKywZM0ACUAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Primed:BAABNQAECoEgAAIRAAgK2g4xDQDaAQARAAgK2g4xDQDaAQAAAA==.',
Pu='Pungla:BAAANQAECggICgAAAA==.',
Qu='Quelthanos:BAABNQAECoEXAAMjAAcK2Q+AjACjAQAjAAcK2Q+AjACjAQAKAAEKfBBQ6AA/AAAAAA==.',
Ra='Radical:BAAANQAECgMIBAAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rapsodii:BAAANQADCgcJCAAAAA==.Rascalfats:BAAANQAECgMIAwABNQAECgQICAABAAAAAA==.Rashii:BAAANQAECgUIDAAAAA==.Raworrior:BAAANQAECgUICwAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECoEeAAIYAAkKbRljEgCvAgAYAAkKbRljEgCvAgABNQADCgIIAgABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Remoria:BAAANQAECgUICwAAAA==.Renildan:BAAANQAECgMIBAAAAA==.Rezputan:BAAANQADCggICAAAAA==.',
Rh='Rhavin:BAAANQADCgYIBgAAAA==.Rholand:BAABNQAECoEeAAIMAAcKHx14XQAuAgAMAAcKHx14XQAuAgAAAA==.',
Ri='Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAAANQAECgQIEgAAAA==.',
Ro='Rollo:BAAANQADCgIIBAAAAA==.Roottender:BAAANQADCgYICgAAAA==.Rovyr:BAABNQAECoEaAAMdAAcKXx1bEgBYAgAdAAcKXx1bEgBYAgAkAAEKlgQCHwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAAANQAECgYIEwAAAA==.',
Ry='Rybearkin:BAAANQADCgIIAgAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAAANQAECgYJEgAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgcIGgATAKEWAA==.Saitamå:BAABNQAECoEeAAIhAAcKJBkFEwD5AQAhAAcKJBkFEwD5AQAAAA==.Samanaras:BAABNQAECoEXAAMMAAgKrhBvfQDOAQAMAAgKyA5vfQDOAQAlAAYKIBGvGQA7AQAAAA==.Sangwyn:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECoEaAAIKAAgKxhpiKQCMAgAKAAgKxhpiKQCMAgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAAANQAECgEIAQAAAA==.',
Sc='Scatterbrain:BAAANQADCgUJBQAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECggIIQAWABkdAA==.Seleine:BAABNQAECoEhAAIWAAgKGR3VAgCuAgAWAAgKGR3VAgCuAgAAAA==.Seloric:BAAANQAECgUICwAAAA==.Serendrin:BAABNQAECoEaAAIIAAgKiB+RDQDfAgAIAAgKiB+RDQDfAgAAAA==.Sevalandre:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.',
Sh='Shadowskyz:BAAANQAECgQIBgABNQAECgkJKQALAGAZAA==.Shaggimaggi:BAAANQAECgUIBgAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAABNQAECoEpAAILAAkKYBniJwCnAgALAAkKYBniJwCnAgAAAA==.Shamorex:BAAANQAECgUIDwAAAA==.Shatter:BAAANQAECgYIEAAAAA==.Shax:BAAANQADCggICAABNQAECgkJIQAZAGwfAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAECgkJKQALAGAZAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAAANQAECgQICgAAAA==.Slyrak:BAAANQADCgYIEQAAAA==.',
Sn='Snackie:BAAANQAECgUIBgAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJLQAZALUSAA==.Sourpunchkid:BAAANQADCggIHwAAAA==.',
Sp='Spacedemon:BAAANQAECgUIBwAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECoEXAAIHAAcKZA+ubgDaAQAHAAcKZA+ubgDaAQAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECoEWAAIDAAcKiRpvJQAiAgADAAcKiRpvJQAiAgAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQADCgYIEQAAAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgMIAwAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIJAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgYICwAAAA==.Sumonmyface:BAABNQAECoEaAAMTAAcKoRYGLwD5AAASAAQKVxLOswADAQATAAMKWBwGLwD5AAAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAAANQAECgUICgAAAA==.',
Sw='Swamprot:BAAANQAECgUICwAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgYICwAAAA==.Syrel:BAAANQAECgEIAgAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Taylorswift:BAAANQAECgYIDwAAAA==.',
Tc='Tchiratha:BAAANQADCgIIAgABNQAECgcIFwAjANkPAA==.',
Te='Tednougat:BAAANQADCgUIBQAAAA==.Telain:BAAANQAECgYIEgAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCgYICwAAAA==.Thakilla:BAABNQAECoEfAAIcAAgKtxCpNQDxAQAcAAgKtxCpNQDxAQAAAA==.Thordrik:BAAANQADCggIFAAAAA==.Thorix:BAAANQAECgUICQAAAA==.Thornhub:BAAANQAECggICAABNQAFFAgIIwAmAEgcAA==.',
Ti='Tiammanth:BAAANQAECgEIAQAAAA==.Tigerbrew:BAAANQADCgUJBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgIIBAAAAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIJAgAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAAANQAECgUICwAAAA==.',
Un='Unholyheart:BAAANQADCgEIAQAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggICAAAAA==.Venari:BAAANQAECgUICwAAAA==.',
Vi='Vilelyn:BAAANQAECgQIBQABNQADCgEIAQABAAAAAA==.Viloria:BAAANQAECgUICwAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAAANQAECgYIEQAAAA==.',
Vl='Vladimor:BAAANQAECgEIAgAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Vozrezz:BAAANQAECgMIAwAAAA==.',
['Vë']='Vëda:BAABNQAECoEaAAIXAAgKRBy/KwB7AgAXAAgKRBy/KwB7AgAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAECgkJIwAnAIImAA==.Warage:BAAANQADCgYIBwAAAA==.Warske:BAAANQADCgcIGQABNQAECgQIBwABAAAAAA==.',
Wh='Wheaties:BAAANQAECgQIBAABNQAECggIHwAPAAAZAA==.Whizzie:BAABNQAECoEtAAIZAAkKtRK3fQBJAgAZAAkKtRK3fQBJAgAAAA==.Whizzlecrank:BAABNQAECoEhAAIZAAgKsRGrnQD/AQAZAAgKsRGrnQD/AQAAAA==.',
Wi='Wicker:BAABNQAECoEcAAMcAAcKShl4NAD5AQAcAAYKzRt4NAD5AQAFAAIKlwmMTgBsAAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgcIHAAcAEoZAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQAECgIIAwAAAA==.Wrectt:BAAANQAECgUICQAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQICAAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECoEXAAIjAAcKoQxsnwB0AQAjAAcKoQxsnwB0AQAAAA==.',
Xe='Xed:BAAANQAECggIEwAAAA==.Xenogears:BAAANQAECggIDwAAAA==.',
Xi='Xiansai:BAABNQAECoEXAAIVAAcKcA/1JQCtAQAVAAcKcA/1JQCtAQAAAA==.',
Ya='Yappey:BAAANQAECgYIBgAAAA==.',
Yi='Yippee:BAAANQADCggIEAAAAA==.',
Yo='Youthinasia:BAAANQAECgUICwAAAA==.',
Ze='Zerega:BAAANQADCgcIEwABNQAECgYIJAAIAOwJAA==.',
Zh='Zhi:BAAANQAECgMIBAAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Zo='Zombiehippo:BAAANQAECggIEgAAAA==.',
['Áu']='Áutarch:BAAANQAECgQICgAAAA==.',
['Ðe']='Ðemøn:BAAANQADCgYIFQAAAA==.',
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
