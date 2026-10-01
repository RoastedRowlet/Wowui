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

local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Mage-Arcane','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Warrior-Arms','Paladin-Retribution','Druid-Guardian','Paladin-Holy','Evoker-Preservation','Warrior-Fury','Mage-Frost','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Rogue-Assassination','DeathKnight-Unholy','Shaman-Restoration','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Frost','Druid-Restoration','DeathKnight-Blood','Paladin-Protection','Hunter-Survival','DemonHunter-Devourer','Evoker-Augmentation','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-09-29',data={Ah='Ahpuch:BAABNQAECoEgAAIBAAkK+BSOHABuAgABAAkK+BSOHABuAgAAAA==.',
Ai='Aidasul:BAAANQAECgUICgAAAA==.',
Al='Aldesca:BAAANQAECgUICgAAAA==.',
An='Ancile:BAAANQAECgQIBgAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgcIDgAAAA==.',
Ar='Armstrõng:BAAANQAECgIJAgAAAA==.',
As='Ashaxxi:BAAANQAFFAEIAgAAAA==.Ashpaw:BAAANQAECgcIEwABNQAFFAEIAgACAAAAAA==.Aspen:BAAANQAECgEIAQAAAA==.',
At='Atcjedi:BAAANQAECgQIBgAAAA==.Atmospherewr:BAAANQAECggIDAABNQAFFAYIEwADAHwhAA==.Atmospherez:BAACNQAFFIETAAIDAAYKfCEtAwBcAgADAAYKfCEtAwBcAgA1AAQKgSAAAgMACQqyJS0ZAF8DAAMACQqyJS0ZAF8DAAAA.',
Av='Avaniah:BAAANQAECgYIEQAAAA==.',
Az='Azmodan:BAAANQADCgcIBwAAAA==.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQAECgUIBQAAAA==.Baep:BAAANQAECgUICQAAAA==.Bandrago:BAAANQAECgYIDwAAAA==.Batmeng:BAAANQAECgIJAgAAAA==.',
Bb='Bbirog:BAAANQAECgcIBQABNQAECgcIDQACAAAAAA==.',
Be='Beaulioh:BAAANQAECgcIDQAAAA==.Bekzarn:BAAANQAECgEIAQABNQAECgYIDgACAAAAAA==.Benfrank:BAABNQAECoEYAAIEAAgKuRWxMQAOAgAEAAgKuRWxMQAOAgAAAA==.Bernthul:BAAANQAECgUIDAAAAA==.Bethan:BAAANQAECgYIEQAAAA==.',
Bl='Blaart:BAABNQAECoEeAAQFAAgKfxf4WQD7AQAFAAcK+Rb4WQD7AQAGAAIKrxZLSQCOAAAHAAEK4QeEKQAvAAAAAA==.Blackwaters:BAABNQAECoEXAAMIAAcKzyEMCQC0AgAIAAcKzyEMCQC0AgAJAAUK0xYogQBLAQAAAA==.Blax:BAAANQAECgcIEQAAAA==.Blindcow:BAABNQAECoEjAAIKAAkKfB7fLQDXAgAKAAkKfB7fLQDXAgAAAA==.Blindhugs:BAAANQAECgcIEAAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgYIBQAAAA==.Blùey:BAAANQADCgYIBgABNQAECgkJIAALAAMeAA==.',
Bo='Bodytypebig:BAABNQAECoEsAAIMAAgKshQmDwDuAQAMAAgKshQmDwDuAQAAAA==.Boicrystian:BAAANQAECgIIBAAAAA==.Bolillo:BAAANQADCgcIDAABNQAECgcIDQACAAAAAA==.Bomie:BAAANQADCgUIBQAAAA==.Bookitty:BAAANQADCggIGAAAAA==.Boosty:BAABNQAECoEdAAIKAAgKmx/vMQDHAgAKAAgKmx/vMQDHAgAAAA==.Bossladie:BAAANQADCgEJAQAAAA==.Bossladìe:BAABNQAECoElAAINAAkKHhZcJgCcAgANAAkKHhZcJgCcAgAAAA==.Boston:BAAANQADCgUIBQAAAA==.',
Br='Brewholic:BAAANQAECgYIDQAAAA==.Bristle:BAABNQAECoEgAAMJAAgKSSC6IQDMAgAJAAgKSSC6IQDMAgAIAAMKORU8IADdAAAAAA==.Brommix:BAAANQADCgMIBgAAAA==.Brotem:BAAANQAECggIBwAAAA==.Broxy:BAAANQAECgEIAQAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDgAAAA==.Bullshiitake:BAABNQAECoEWAAINAAgK+w7wVQDQAQANAAgK+w7wVQDQAQAAAA==.',
['Bö']='Bönezone:BAAANQADCgQIBAAAAA==.',
Ca='Calaglin:BAABNQAECoEbAAQFAAgKCxUPYwDeAQAFAAcKFhQPYwDeAQAGAAEKvBupXgBRAAAHAAEKsgGSLAAXAAAAAA==.Calelorian:BAAANQADCgYICgAAAA==.Catstack:BAAANQAECgEIAQAAAA==.',
Ce='Celdiirn:BAAANQADCggIEwAAAA==.Celesti:BAABNQAECoEYAAILAAYKPxFepQBmAQALAAYKPxFepQBmAQAAAA==.',
Ch='Chiky:BAAANQAECgIIAwAAAA==.Choom:BAAANQAECgUICAAAAA==.Chubsy:BAAANQAECggIDQAAAA==.Chuckkyd:BAAANQAECgYIEwAAAA==.',
Cl='Claugh:BAAANQAECggIEwAAAA==.Cleb:BAAANQAFFAIIAgAAAA==.Clocker:BAAANQAECgYICgAAAA==.Clumbsykoala:BAAANQAECgUICgAAAA==.',
Co='Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAACNQAFFIESAAIOAAYKWxaJAwATAgAOAAYKWxaJAwATAgA1AAQKgSAAAg4ACQr4EuESAFECAA4ACQr4EuESAFECAAAA.Combatcow:BAABNQAECoEdAAIPAAgK7CKrAgAFAwAPAAgK7CKrAgAFAwAAAA==.Contagion:BAAANQAECggICAAAAA==.Coorona:BAAANQADCgcIBwAAAA==.Cozmic:BAABNQAECoEeAAMDAAgKTyP/TwC6AgADAAcKAyP/TwC6AgAQAAMKzSIPFgALAQAAAA==.',
Cr='Craftymidget:BAAANQADCggJCAAAAA==.Crucifixd:BAAANQAECgEIAQAAAA==.Cryptonic:BAAANQAECggICAAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAABNQAECoEeAAIKAAgKLiGIJAAAAwAKAAgKLiGIJAAAAwAAAA==.',
Cu='Curandero:BAABNQAECoEUAAIJAAQKMg+5qADsAAAJAAQKMg+5qADsAAAAAA==.Curie:BAAANQAECgEIAQABNQAECgcIJAARAG4bAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUIBQAAAA==.Dameck:BAABNQAECoEfAAIKAAgKjhHbagAFAgAKAAgKjhHbagAFAgAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCggICgABNQAECgcIDgACAAAAAA==.Dasdots:BAAANQAECgYIBgAAAA==.Dasmuro:BAAANQADCgIIAgABNQAECgUIEgACAAAAAA==.Dazzeler:BAAANQAECgcIDgAAAA==.',
De='Deadeenside:BAAANQADCgYIBgABNQAECgYICgACAAAAAA==.Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAAANQAECgYIEgAAAA==.Delver:BAAANQAECgQICQAAAA==.Demongirly:BAAANQABCgQIBAAAAA==.Demonsue:BAAANQABCgIIAgAAAA==.Denathria:BAAANQAECgcIDwAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAACNQAFFIEVAAMSAAcKQhzUAQAtAgASAAYKyxzUAQAtAgATAAIKPQUwGAC0AAA1AAQKgSEAAhIACQoZJMwEAHQDABIACQoZJMwEAHQDAAAA.Deviourer:BAAANQABCgIIAgAAAA==.Devo:BAAANQABCgIIAgAAAA==.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.Difflect:BAAANQADCgYIBgABNQADCgYIDAACAAAAAA==.',
Do='Doak:BAABNQAECoEkAAMRAAcKbhsbEwAyAgARAAcKbhsbEwAyAgAUAAIKigkXZgB2AAAAAA==.Doonfist:BAAANQABCggIEgAAAA==.Dotz:BAACNQAFFIEHAAMGAAMKAxZXBwC0AAAGAAIKbhdXBwC0AAAFAAEKLxOdLABRAAA1AAQKgSEAAwUACQrUHqdFAEACAAUABwrRHqdFAEACAAYABgp0Dj4gAFoBAAAA.Douchec:BAAANQAECgEIAQAAAA==.',
Dr='Draconius:BAAANQADCgYIFQAAAA==.Draenor:BAAANQAECgEIAgAAAA==.Dragondilly:BAAANQADCgQIBAAAAA==.Dragonforce:BAAANQAECgUIDQAAAA==.Dragonhaze:BAAANQAECgUIDwAAAA==.Dragonskull:BAAANQAECgYJBgAAAA==.Drazentar:BAAANQAECgUIEgAAAA==.Dream:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.Drevox:BAABNQAECoEZAAIVAAcKyhtANgDuAQAVAAcKyhtANgDuAQAAAA==.Druiddruid:BAAANQADCgYICQAAAA==.',
Du='Dulgar:BAABNQAECoEgAAIWAAgKQxojOgAvAgAWAAgKQxojOgAvAgAAAA==.Dumami:BAAANQAECgEJAQABNQAECgIJAgACAAAAAA==.',
['Dë']='Dëlilah:BAAANQAECgIIAgAAAA==.',
Ea='Eaglewarrior:BAAANQADCggIDgAAAA==.',
El='Elind:BAAANQADCgQIBAAAAA==.Elisyum:BAAANQAECgIIAgAAAA==.Elleduff:BAAANQAECgUIDgAAAA==.Eloragon:BAAANQABCgMIAwAAAA==.Elyssabeta:BAAANQADCgQJBAAAAA==.Elysstaa:BAABNQAECoEgAAMTAAgKchrrOgA2AgATAAgKchrrOgA2AgASAAEKXxWyWwA/AAAAAA==.',
En='Entïty:BAAANQADCgcIDgABNQAECgQICAACAAAAAA==.',
Eo='Eogden:BAAANQAECgYICgAAAA==.',
Eq='Equilibria:BAAANQAECgUICgAAAA==.',
Er='Erida:BAAANQAECgIJAgAAAA==.Ers:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.',
Et='Etík:BAAANQAECgUICAAAAA==.',
Ev='Evocative:BAACNQAFFIEFAAIXAAIKwhfcCACYAAAXAAIKwhfcCACYAAA1AAQKgRwAAhcACQrCHqYHAN4CABcACQrCHqYHAN4CAAAA.',
Ex='Exaltso:BAAANQADCgYIDwAAAA==.',
Ey='Eyebright:BAAANQAECgIIAwAAAA==.Eyye:BAAANQADCgQIBgABNQAECgQIBAACAAAAAA==.',
Fa='Farns:BAACNQAFFIEOAAMDAAUKjSBaCwDXAQADAAUKsR1aCwDXAQAQAAIKQRvgAwCqAAA1AAQKgSAAAwMACQpUJZgMAJcDAAMACQouJZgMAJcDABAABAobJhoQAF4BAAAA.Fawndolynn:BAAANQAECgQICwAAAA==.',
Fe='Felinepriest:BAAANQAECgUIDwAAAA==.Felovan:BAAANQADCgcICAAAAA==.Felsoaked:BAAANQAECgEIAgAAAA==.Felstehr:BAAANQAECgUIDwAAAA==.Feltotes:BAAANQAECgQIBAAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAABNQAECoEaAAIWAAkKbSC2EAAWAwAWAAkKbSC2EAAWAwAAAA==.Firebäne:BAABNQAECoEYAAIGAAcKqB7UBwBzAgAGAAcKqB7UBwBzAgAAAA==.Fistnor:BAAANQAECgEIAQAAAA==.',
Fl='Flaminghawk:BAACNQAFFIEOAAIDAAUKSRdMDADMAQADAAUKSRdMDADMAQA1AAQKgRoAAgMABwo2IZB1AF0CAAMABwo2IZB1AF0CAAAA.',
Fr='Franklin:BAAANQAECgYICAAAAA==.Frankotronic:BAABNQAECoEYAAIDAAcKQBRDugDAAQADAAcKQBRDugDAAQAAAA==.Frayniac:BAAANQAECgUIBQAAAA==.Freakies:BAAANQADCgQIBgAAAA==.Freyin:BAABNQAECoEgAAIYAAgKXhgEOQB7AgAYAAgKXhgEOQB7AgAAAA==.Frie:BAAANQADCgYIBgAAAA==.Frolgar:BAAANQADCgYICAAAAA==.Frostyflakez:BAAANQAECgEJAQAAAA==.',
Fu='Fullclangg:BAABNQAECoEXAAINAAgKdx0HJQCjAgANAAgKdx0HJQCjAgABNQAFFAcIIQAOAKceAA==.Fulldracarys:BAACNQAFFIEhAAIOAAcKpx4nAQCTAgAOAAcKpx4nAQCTAgA1AAQKgSIAAg4ACQrPIgEGADADAA4ACQrPIgEGADADAAAA.Fullgabagool:BAABNQAECoEeAAITAAkKeB0QFgD0AgATAAkKeB0QFgD0AgABNQAFFAcIIQAOAKceAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAcIIQAOAKceAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCggIGQAAAA==.Ganster:BAAANQAECgQIBAAAAA==.Gaya:BAAANQADCgQICgAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAABNQAFFIEGAAIKAAMKwQX6GgC1AAAKAAMKwQX6GgC1AAAAAA==.',
Gi='Ginyeng:BAAANQAECgcIBwABNQAECgkJIgAOAHIdAA==.',
Gl='Glimpse:BAAANQAECgcIDQAAAA==.',
Gn='Gnomebody:BAAANQAECgIIAwAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBgAAAA==.',
Gr='Greenmonsta:BAAANQADCgUIBQAAAA==.Grimknight:BAABNQAECoEnAAILAAkKRyYABgC5AwALAAkKRyYABgC5AwAAAA==.Groovi:BAAANQADCgUIBQAAAA==.',
Gu='Guycow:BAABNQAECoEcAAINAAkK9R40EwARAwANAAkK9R40EwARAwAAAA==.',
Ha='Hambonë:BAACNQAFFIETAAIEAAYKdiBQAwA2AgAEAAYKdiBQAwA2AgA1AAQKgSIAAgQACQpnJu0BANQDAAQACQpnJu0BANQDAAAA.Hardballs:BAAANQADCgUIBgAAAA==.Hashbrowns:BAABNQAECoEfAAILAAkKByOPDACEAwALAAkKByOPDACEAwAAAA==.Havdk:BAAANQAECgIIAwAAAA==.Haxxorwyn:BAAANQAECgcIDQAAAA==.Hazreil:BAABNQAECoEgAAIMAAgKgxRgDwDpAQAMAAgKgxRgDwDpAQAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIDgAAAA==.Heavenlee:BAAANQAECgUIDwABNQADCggIEwACAAAAAA==.Hecklefish:BAABNQAECoEjAAMYAAkKiCY0AQDrAwAYAAkKiCY0AQDrAwAZAAIKkhz7TQCeAAAAAA==.Hellik:BAAANQABCgMIAwAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAABNQAECoEaAAIJAAgKfA8cUQDkAQAJAAgKfA8cUQDkAQAAAA==.Highdegrees:BAAANQAECgQIBAAAAA==.Hinatta:BAAANQAECgEIAQABNQAECgYIEwACAAAAAA==.Hitagi:BAAANQAECgMICwAAAA==.',
Ho='Hole:BAAANQAECgEIAgAAAA==.Hollo:BAAANQAECgIIAwAAAA==.Holyblasts:BAAANQAECgcIEwAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQABCgMIBAABNQADCgYIBwACAAAAAA==.Horsey:BAAANQAECgYIBwABNQAECggIFwAaAOQeAA==.Hownow:BAAANQADCgIIAgAAAA==.',
Hu='Hummingbird:BAAANQAECgQIBAABNQAECgcIDwACAAAAAA==.Hungus:BAAANQAECgQIBgAAAA==.Hurtszick:BAAANQAECgQIBwAAAA==.',
Hy='Hydrotiger:BAAANQAECgUIBwABNQAECgkJGQASAFYZAA==.',
['Hä']='Härasou:BAAANQADCgYIDQAAAA==.',
Il='Illiturtle:BAAANQAECggIEwAAAA==.',
Im='Imnotthtgood:BAAANQADCggIFAAAAA==.',
In='Indever:BAAANQABCgcICAAAAA==.Indigolemon:BAABNQAECoEcAAMEAAgK2BllIgCEAgAEAAgK2BllIgCEAgAbAAEKxwdhYQAlAAAAAA==.Inkenhancer:BAAANQAECgcIEQAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Iy='Iyari:BAAANQADCgYICwAAAA==.',
Ja='Jaffaar:BAAANQADCggICAAAAA==.Jamie:BAABNQAECoEUAAILAAcKxg13kQCXAQALAAcKxg13kQCXAQAAAA==.',
Je='Jeynsa:BAAANQAECgMIAwABNQAECggIHQAEAKwZAA==.',
Ji='Jingadingado:BAAANQADCgYIBgAAAA==.',
Jo='Jollyollie:BAAANQADCgQIBQAAAA==.Joppy:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQAECgQIBwAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jë']='Jëf:BAAANQADCgIIAgAAAA==.',
['Jô']='Jôker:BAAANQAECgQICQAAAA==.',
Ka='Kacho:BAAANQAECgEIAQAAAA==.Kaelara:BAAANQAECggIBgAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kaorii:BAAANQADCgYIBwAAAA==.Kappo:BAAANQAECgYJCgAAAA==.Kathorall:BAAANQAECgUIEAAAAA==.Kawaiihealer:BAAANQAECgYIEwAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIAwAAAA==.Kemper:BAAANQAECgUIDQAAAA==.Kerrs:BAAANQAECgEIBQAAAA==.Kerrz:BAAANQAECgEIAQAAAA==.',
Ki='Kiddyl:BAAANQADCgYIDwAAAA==.Kidneypopper:BAAANQADCgcICAABNQAECggIHgADAE8jAA==.Kievit:BAAANQAECgYIBwAAAA==.Kir:BAAANQAECgYICgAAAA==.Kittana:BAABNQAECoEYAAINAAcK2RqsPgApAgANAAcK2RqsPgApAgAAAA==.Kittyhawke:BAAANQAECggICwABNQAECggIHAAEANgZAA==.',
Kk='Kkelhus:BAAANQAECgQIBwAAAA==.Kkrantuq:BAABNQAECoEcAAIRAAkKUhHNDwBfAgARAAkKUhHNDwBfAgAAAA==.Kkylar:BAAANQAECgUIBQAAAA==.',
Kl='Klariityy:BAABNQAECoEYAAMTAAkKLAmqTwDeAQATAAkKLAmqTwDeAQASAAEK8A5KZAAtAAAAAA==.Klarity:BAAANQADCgYIBgAAAA==.Klarityqt:BAAANQAECgQIBAAAAA==.Klarityx:BAABNQAECoEjAAIDAAkKExlBTwC8AgADAAkKExlBTwC8AgAAAA==.',
Kn='Knownentity:BAAANQAECgQICAAAAA==.',
Ko='Koma:BAAANQADCggJCAABNQAFFAYIEQAJAM0iAA==.Komatos:BAACNQAFFIERAAIJAAYKzSJyAQB+AgAJAAYKzSJyAQB+AgA1AAQKgScAAgkACQqDJi8CANoDAAkACQqDJi8CANoDAAAA.Koreantacos:BAAANQADCgcIDQAAAA==.Koronus:BAAANQADCgcIFwAAAA==.',
Kr='Kracklin:BAAANQADCgYIBgAAAA==.',
Ks='Ks:BAAANQADCggIDgABNQAECgQIBgACAAAAAA==.',
Ku='Kurisutina:BAAANQAECgQICAAAAA==.',
['Kâ']='Kânamë:BAAANQADCggICAABNQAECgcIGgAVALYSAA==.',
['Kê']='Kênsêi:BAABNQAECoEaAAIVAAcKthIBSwCDAQAVAAcKthIBSwCDAQAAAA==.',
['Kô']='Kôan:BAAANQAECgUICAAAAA==.',
La='Lanatec:BAAANQAECgIIBAAAAA==.Largetimmy:BAAANQADCggICQABNQAECgcIDQACAAAAAA==.',
Le='Leafyjoe:BAABNQAECoEZAAIEAAcK2hzRKgBCAgAEAAcK2hzRKgBCAgAAAA==.Lechencaja:BAAANQADCgYJBgABNQAECgYICwACAAAAAA==.Legendarybob:BAAANQADCgYJBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAABNQAECoEdAAQVAAcKOwjSXQAzAQAVAAcK/wbSXQAzAQAcAAcKTwUIaAAIAQAaAAMK2wIOcwBhAAAAAA==.Legö:BAAANQAECggIBQABNQAECggIHQAVADsIAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECggIGAAUAGYcAA==.',
Li='Libidine:BAAANQADCgIIAgABNQAECgUICgACAAAAAA==.Lido:BAAANQAECggIEAAAAA==.Lilcowdk:BAAANQADCgEIAQABNQAECgkJHgAGADsZAA==.Lildeemon:BAABNQAECoEeAAMGAAkKOxmnDAAbAgAGAAcKSBinDAAbAgAFAAcKyxRNZADbAQAAAA==.Lilspyro:BAAANQAECgQIBAAAAA==.Livathian:BAABNQAECoEaAAILAAcKzAw1mgCBAQALAAcKzAw1mgCBAQAAAA==.Lizwiz:BAAANQAECgYIBgAAAA==.',
Lo='Lokrah:BAAANQABCgMIBgAAAA==.',
Lu='Lucerubis:BAAANQAECgYIBgAAAA==.Lucifiux:BAAANQAECgcIEQAAAA==.Lunavel:BAABNQAECoEeAAMLAAcKrhWtkACZAQALAAYKCxitkACZAQAdAAUK2w4PNADrAAAAAA==.',
Ly='Lydo:BAAANQAECggICwAAAA==.',
Ma='Maggette:BAAANQADCgYIBgABNQAECgYIEgACAAAAAA==.Magicdan:BAAANQADCgYICAAAAA==.Malnorr:BAABNQAECoEYAAMFAAcKABZecAC2AQAFAAYKrxZecAC2AQAGAAIKhxJ3TwB7AAAAAA==.Mandragon:BAAANQADCgUIBQABNQAECgkJHAANAPUeAA==.Mangol:BAAANQAECgcIDgAAAA==.Manudei:BAAANQAECgcIBwAAAA==.Marryg:BAAANQADCggICAABNQAECggIDQACAAAAAA==.Maryillo:BAACNQAFFIERAAIEAAYKSh3iAwAbAgAEAAYKSh3iAwAbAgA1AAQKgSIAAgQACQr8JNMKAF0DAAQACQr8JNMKAF0DAAAA.Mattdaemon:BAAANQAECgYICwAAAA==.',
Mc='Mcmannis:BAAANQAECgcIBwAAAA==.Mcpoltrain:BAAANQAECgUIBwAAAA==.',
Me='Mennil:BAAANQAECgUIBwAAAA==.Meolater:BAABNQAECoEaAAIOAAcKLhvQFAAzAgAOAAcKLhvQFAAzAgAAAA==.Mesmerise:BAAANQAECgYICgAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECggIGAAUAGYcAA==.Mindgoblinn:BAAANQAECgYIDgAAAA==.Minicookie:BAAANQADCgEIAgAAAA==.Minyaw:BAAANQAECgMIBAABNQAECgcIJAARAG4bAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQAECgQICwAAAA==.',
Mm='Mmchocolat:BAAANQAECgIIAgAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEBNQAECoEgAAIeAAgK3R8JAgACAwAeAAgK3R8JAgACAwAAAA==.Moolissa:BAAANQAECgYIEgAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgMIBgAAAA==.Morbidchaos:BAACNQAFFIESAAIfAAYK0iC6AQBOAgAfAAYK0iC6AQBOAgA1AAQKgSMAAh8ACQqwImMHAEkDAB8ACQqwImMHAEkDAAAA.Morkels:BAAANQAECgcIDAABNQAFFAgIHwAgALoiAA==.',
Mu='Muddyshark:BAAANQAECgcIEQAAAA==.Mukatsuku:BAAANQAECgUICQAAAA==.Muscida:BAAANQAECgEIAQAAAA==.',
My='Mykhawk:BAAANQADCgUICAAAAA==.',
Na='Naeth:BAABNQAECoEdAAILAAgKVBwdRAB9AgALAAgKVBwdRAB9AgAAAA==.Nalrot:BAAANQADCggIDwABNQAECgYICgACAAAAAA==.Narcine:BAAANQAECggIEwAAAA==.',
Ne='Neciecakes:BAABNQAECoEgAAMNAAgKzhKPRgAKAgANAAgKzhKPRgAKAgALAAEK4BAgQQE7AAAAAA==.Nee:BAABNQAECoEfAAMWAAkKFhKlQAATAgAWAAkKFhKlQAATAgAJAAUKuBAmiAA4AQAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nekus:BAAANQADCgcIBwAAAA==.Nelor:BAAANQAECgYIEgAAAA==.Nerftitty:BAAANQADCgUIBQAAAA==.Nettles:BAAANQAECgIIAgAAAA==.Neverheal:BAAANQADCgEIAQAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ng='Ngàymai:BAAANQADCgQIBAAAAA==.',
Ni='Nightwatchr:BAAANQAECgcIDAAAAA==.Nisona:BAAANQAECgQIBQAAAA==.Nitashal:BAABNQAECoEiAAMOAAkKch0ECgDjAgAOAAkKch0ECgDjAgAXAAEKoA45MwA2AAAAAA==.',
No='Nokthro:BAAANQADCgYJBgABNQAECgkJJwAXANEfAA==.Noremac:BAAANQADCgYIDAAAAA==.',
Nu='Nubsaiboot:BAAANQAECgUIBQABNQAECgYICgACAAAAAA==.',
Ny='Nythariel:BAAANQADCggIGgAAAA==.',
['Në']='Nëzükõ:BAAANQADCgYIBgABNQAECgcIGgAVALYSAA==.',
Od='Odi:BAAANQAECgMIAwAAAA==.',
Ok='Okiaat:BAAANQAECgQIBgAAAA==.',
Ol='Oliviawildè:BAABNQAECoEZAAMNAAkKBBrcFAAFAwANAAkKBBrcFAAFAwALAAEKjwJpbAEhAAAAAA==.',
On='Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAAANQAECgYIDgAAAA==.Pallyforhire:BAAANQAECgEIAQAAAA==.Panfriedrice:BAAANQAECggIBAAAAA==.Pantyblossom:BAAANQAECgUICgABNQAECgYIEgACAAAAAA==.',
Pe='Peaches:BAAANQAECgQIBgAAAA==.Peewees:BAAANQADCgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAABNQAECoEeAAIGAAcKUB+0CgA6AgAGAAcKUB+0CgA6AgAAAA==.Peladin:BAAANQABCgcJDAAAAA==.Pelado:BAAANQABCgIIAgAAAA==.Pelito:BAAANQADCgUJBQAAAA==.Pell:BAAANQADCgEIAQAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQAECgIIAgABNQAECggIIAAKANUQAA==.',
Ph='Phaeddrus:BAAANQAECgQIBQAAAA==.Phobos:BAAANQAECgYICwAAAA==.Phogood:BAAANQAECgMIAwAAAA==.Phrix:BAAANQADCgUIBgABNQAECgkJJwAXANEfAA==.',
Pi='Pinecone:BAABNQAECoEbAAIEAAkKbSNcEQAbAwAEAAkKbSNcEQAbAwAAAA==.',
Pl='Ploppster:BAAANQADCggIDQAAAA==.Plot:BAAANQAECggIDgAAAA==.',
Po='Poekimaw:BAAANQAECgEIAQAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAABNQAECoEfAAILAAkKvSWlCAChAwALAAkKvSWlCAChAwAAAA==.Poppinin:BAAANQAECgYIEAAAAA==.Potaters:BAAANQADCgQIBAAAAA==.Potshotbot:BAAANQADCgYIBgAAAA==.Powerwordhug:BAAANQAECgYIDAABNQAECgcIEAACAAAAAA==.',
Pr='Praedo:BAAANQADCgYJBgAAAA==.Prevaleon:BAAANQAECgEIAQAAAA==.',
Ps='Psychaos:BAAANQAECgcIBwAAAA==.Psychostorm:BAAANQAECgEIAQAAAA==.Psychritic:BAAANQAECgcJEwAAAA==.Psyence:BAAANQADCgcIDgAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purpletotem:BAAANQADCgYIBgAAAA==.Purrsnikitty:BAAANQADCggIEwAAAA==.Pus:BAAANQADCgYIBgAAAA==.',
Qo='Qookd:BAAANQAECgIIAgAAAA==.',
Qu='Quillmane:BAAANQADCggIFgABNQAECgkJJwAXANEfAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAABNQAECoEhAAIfAAgKOx6sEgCrAgAfAAgKOx6sEgCrAgAAAA==.Ragingdeath:BAAANQADCgYIBwAAAA==.Rainakamugi:BAAANQAECgQJBwABNQAECgkJHwATACsVAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQAECgQIBgAAAA==.Ralphanir:BAAANQAECgUIDwAAAA==.Raskreia:BAAANQADCggICQAAAA==.Raygyu:BAAANQADCgQIBAABNQAFFAEIAQACAAAAAA==.Rayvoker:BAAANQADCgYJDAABNQAFFAEIAQACAAAAAA==.',
Re='Reek:BAAANQAECgYIEgAAAA==.Rexari:BAAANQAECgQIEQAAAA==.Rezmae:BAAANQAECgEIAgAAAA==.',
Ri='Riniedaze:BAAANQADCgUICgAAAA==.',
Ro='Rockandstone:BAACNQAFFIEGAAINAAUKSgJNCwA/AQANAAUKSgJNCwA/AQA1AAQKgSsAAg0ACQqpFusoAI8CAA0ACQqpFusoAI8CAAAA.Rocki:BAAANQAECgEJAQABNQAFFAMIBwAGAAMWAA==.Rooty:BAAANQAECgQIBgAAAA==.Roron:BAAANQAECgQIBAAAAA==.',
Sa='Safetyspork:BAAANQAECgQIBAAAAA==.Sagë:BAAANQAECgUICgAAAA==.Sakonutz:BAAANQAECgYIEwAAAA==.Salsa:BAAANQADCgcIDwAAAA==.Saresh:BAAANQAFFAIIAwAAAA==.Sathariel:BAAANQABCgIJAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.',
Sc='Schlee:BAAANQABCgYJCAAAAA==.Screeps:BAAANQABCgcIDgABNQADCgYIBwACAAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAAANQAECgYIEgAAAA==.Selceor:BAAANQADCggICAAAAA==.Sendh:BAAANQAECgUJCQAAAA==.Sermet:BAAANQAECgUICQABNQAECgcIEQACAAAAAA==.Sermonn:BAAANQAECgQIBQAAAA==.Serous:BAAANQAECgQICgAAAA==.Serwellmet:BAAANQADCgMIAwABNQAECgcIEQACAAAAAA==.Seshin:BAAANQAECggJIgAAAQ==.Setal:BAABNQAECoEnAAIXAAkK0R8aBQAiAwAXAAkK0R8aBQAiAwAAAA==.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgcIJAARAG4bAA==.Shammoo:BAAANQAECgIJAgAAAA==.Shcho:BAAANQAECgEIAQAAAA==.Sheepe:BAAANQAECgUICwAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgQIBAAAAA==.Shinyscalp:BAAANQAECggIDgAAAA==.Shkanna:BAAANQAECggIBwAAAA==.Shogunz:BAAANQAECgUJBgAAAA==.',
Si='Simaria:BAAANQADCggIFAAAAA==.Sinapaladin:BAAANQAECgUIDQABNQAECgYICgACAAAAAA==.Siomara:BAAANQAECgUIEAAAAA==.Sivanya:BAAANQADCgYJBgAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgYIBwAAAA==.Skrepz:BAAANQABCgIJAgABNQADCgYIBwACAAAAAA==.Skypri:BAAANQADCgcIBwAAAA==.',
Sl='Slabbster:BAAANQAECgQIBgAAAA==.',
Sm='Smooshednewt:BAABNQAECoElAAIIAAgKNyGPBQARAwAIAAgKNyGPBQARAwABNQAECgkJGQASAFYZAA==.',
Sn='Sne:BAAANQAECgQICQAAAA==.Snoop:BAAANQAECgcICwAAAA==.',
So='Soloa:BAAANQAECgIIAgAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAABNQAECoEdAAIEAAgKrBn4IwB3AgAEAAgKrBn4IwB3AgAAAA==.Sosneaky:BAAANQADCgMICAAAAA==.Soulfuria:BAAANQAECggIBwAAAA==.',
Sp='Spekk:BAAANQADCgYICgAAAA==.Speknawz:BAABNQAECoEYAAMRAAkKFRbWDwBeAgARAAkKWRPWDwBeAgAUAAMK2xm8UADjAAAAAA==.Splatzill:BAAANQADCgIIAgABNQAECgkJKQAKAIYZAA==.Spoiledangel:BAAANQAECgUIDwAAAA==.Spoonhat:BAAANQADCgcICwABNQAECgQIBAACAAAAAA==.Springz:BAAANQAECgUICgAAAA==.',
St='Staggering:BAAANQAECgcIEQAAAA==.Starryniight:BAAANQAECgQIBwAAAA==.Stephsux:BAAANQAECgUIDAAAAA==.Stickers:BAAANQAECgMJBAAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgYIBwAAAA==.Suika:BAAANQAECgQIBAAAAA==.Supanova:BAABNQAECoEZAAMSAAkKVhlaEgCcAgASAAgKJBtaEgCcAgATAAEK9htXvQBVAAAAAA==.Surwick:BAAANQAECgYICwAAAA==.',
Sv='Svelus:BAACNQAFFIEPAAILAAYKuiLaAACCAgALAAYKuiLaAACCAgA1AAQKgSMAAgsACQoGJsoIAKADAAsACQoGJsoIAKADAAAA.',
Sw='Swingin:BAAANQAECgYIEgAAAA==.',
Sy='Sycophancy:BAAANQAECgEIAQAAAA==.Synaptichole:BAAANQAECgQIBgAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tachealz:BAAANQAECgcIEQAAAA==.Tanurhide:BAAANQADCgQIBAAAAA==.Tartan:BAAANQAFFAIIAwAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.Taylorswif:BAAANQADCgEIAQABNQAECgkJIgAQAHkhAA==.',
Te='Tearal:BAAANQADCgEIAQAAAA==.Techi:BAAANQADCgIIAgAAAA==.Teewat:BAAANQADCgUIBQAAAA==.Temres:BAAANQAECgcIEQAAAA==.Tendermulva:BAAANQAECgYIEwAAAA==.Terekk:BAAANQADCgYIEgAAAA==.Teshtara:BAAANQADCggIEAABNQAECggIHQAEAKwZAA==.',
Th='Theod:BAAANQADCgYIBwAAAA==.Thesauce:BAACNQAFFIELAAMhAAUKjx2TAgBbAQAiAAQK/B3hBAB/AQAhAAQKNBqTAgBbAQA1AAQKgSEAAyIACQodJVgEAHYDACIACQq+JFgEAHYDACEABwoSI/MFALgCAAAA.Thiaw:BAAANQAECgIIAgAAAA==.Thimo:BAAANQADCgEIAQABNQADCggICQACAAAAAA==.Thrikal:BAABNQAECoEgAAIBAAgKOg/pLADjAQABAAgKOg/pLADjAQAAAA==.',
To='Tomsmg:BAABNQAECoEfAAMDAAkKxhjkXgCUAgADAAkKxhjkXgCUAgAQAAEKdAcqOgA0AAAAAA==.Toofs:BAAANQAECgYICwAAAA==.Toxifay:BAAANQAECgUJCQAAAA==.',
Tr='Traell:BAAANQADCgYIDAABNQAECgkJIgABANgfAA==.Trd:BAAANQABCggICgAAAA==.Treehuggles:BAAANQAECgQIBgABNQAECgcIEAACAAAAAA==.Truedat:BAAANQADCgQIBwAAAA==.',
['Tì']='Tìõ:BAAANQADCgYIBgABNQAECgcIGgAVALYSAA==.',
Ug='Ughtismo:BAAANQADCgUJBQAAAA==.',
Un='Undeadban:BAAANQABCgcJCQAAAA==.',
Us='Usagiknight:BAAANQAECgYIDgAAAA==.Ushii:BAAANQAECgQIDQAAAA==.',
Va='Valdemort:BAAANQADCgQIBAABNQAECgQIBAACAAAAAA==.Valei:BAAANQAECgMIAwAAAA==.',
Ve='Veganforlife:BAAANQADCgIIAwAAAA==.',
Vi='Vinda:BAABNQAECoEgAAISAAgKFRlFGABMAgASAAgKFRlFGABMAgAAAA==.Vivixia:BAAANQAECgYICwAAAA==.',
Vo='Volgrath:BAAANQAECggICAAAAA==.Voodoolock:BAAANQAECgQIDgABNQAECgcIEQACAAAAAA==.',
Wa='Walkingboot:BAAANQADCgQIBAAAAA==.Wallo:BAABNQAECoEgAAIKAAgK1RBwdADpAQAKAAgK1RBwdADpAQAAAA==.Washedbolt:BAAANQAECgEIAQAAAA==.Washedpyro:BAAANQAECgIIAwAAAA==.Washedzebu:BAABNQAECoEaAAMUAAcKrRlYIwALAgAUAAcKrRlYIwALAgARAAUKVw7NLQAZAQAAAA==.Watsatotem:BAAANQAECgEJAQAAAA==.Wayfairkid:BAAANQAECgEIAQAAAA==.',
We='Weeb:BAACNQAFFIEfAAIgAAgKuiIaAABxAwAgAAgKuiIaAABxAwA1AAQKgSEAAyAACQqtJpkAALMDACAACQqtJpkAALMDABcACAqQGicRAAUCAAAA.',
Wh='Whiterabbitt:BAAANQADCggILwAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQAECgEIAQAAAA==.Wilmabfiymr:BAAANQAECgEIAQAAAA==.',
Wo='Woa:BAAANQADCggIEgAAAA==.Woofwoofwoof:BAAANQAECgQICQAAAA==.',
Wr='Writhe:BAAANQABCgQICAABNQAFFAcIEQAhAGsiAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Xq='Xquori:BAAANQADCgMIAwAAAA==.',
Ye='Yeeloow:BAAANQADCgYIDQAAAA==.',
Ys='Yshaarj:BAAANQADCggIEgAAAA==.',
Yu='Yulok:BAACNQAFFIERAAIhAAcKayITAADMAgAhAAcKayITAADMAgA1AAQKgR8AAiEACQqVJnQAAOMDACEACQqVJnQAAOMDAAAA.Yuukí:BAAANQADCggICAABNQAECgkJIAALAAMeAA==.',
['Yú']='Yúúki:BAAANQAECgcIEgABNQAECgkJIAALAAMeAA==.',
Za='Zaberra:BAABNQAECoEYAAIHAAgKKxThBAA/AgAHAAgKKxThBAA/AgABNQAECggIHQAEAKwZAA==.Zanarkand:BAAANQAECgUIDAAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zerofort:BAAANQAECgYIBgAAAA==.Zexexe:BAAANQAECgcIDQABNQAFFAYIEwAEAHYgAA==.',
Zi='Zibroth:BAAANQAECgcIEwAAAA==.Zieg:BAAANQAECgUJBQAAAA==.Zina:BAAANQAECgIIAgAAAA==.',
['Áo']='Áodh:BAAANQADCggICAAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQAECgQICAAAAA==.',
['Ýu']='Ýuuki:BAABNQAECoEgAAILAAkKAx5gMgDBAgALAAkKAx5gMgDBAgAAAA==.',
['ßr']='ßrß:BAAANQAECgEIAwAAAA==.',
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
