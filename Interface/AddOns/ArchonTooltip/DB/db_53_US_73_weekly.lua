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

local lookup = {'DemonHunter-Havoc','Druid-Balance','DeathKnight-Blood','Monk-Brewmaster','Mage-Arcane','Mage-Frost','Warrior-Protection','Shaman-Enhancement','Shaman-Elemental','Evoker-Devastation','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Warrior-Arms','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Preservation','Rogue-Subtlety','Hunter-BeastMastery','Priest-Holy','Rogue-Assassination','Shaman-Restoration','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Restoration','Hunter-Survival','Paladin-Protection','Evoker-Augmentation','Priest-Discipline',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adderall:BAAANQAECgEIAQAAAA==.',
Ah='Ahpuch:BAABNQAECoEnAAIBAAkKLBe8GgCgAgABAAkKLBe8GgCgAgAAAA==.',
Ai='Aidasul:BAAANQAECgUIEQAAAA==.',
Al='Aldesca:BAAANQAECgUIDgAAAA==.',
Am='Amarilli:BAAANQADCgMIAwABNQAECgkJJAACAKwZAA==.',
An='Ancile:BAAANQAECgUICAAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgcIDwAAAA==.',
Ar='Armstrõng:BAAANQAECgQIBgAAAA==.',
As='Ashaxxi:BAABNQAFFIEFAAIDAAMKPgO6GQCbAAADAAMKPgO6GQCbAAAAAA==.Ashpaw:BAABNQAECoEXAAIEAAgKzQusFQBmAQAEAAgKzQusFQBmAQABNQAFFAMIBQADAD4DAA==.Aspen:BAAANQAECgEIAgAAAA==.',
At='Atcjedi:BAAANQAECgQIBwAAAA==.Atmospherewr:BAAANQAECggIEAABNQAFFAcIGQAFAPMiAA==.Atmospherez:BAACNQAFFIEZAAMFAAcK8yIBBQBOAgAFAAYKYiIBBQBOAgAGAAEKWyaVBwB0AAA1AAQKgSAAAgUACQqyJQUhAE0DAAUACQqyJQUhAE0DAAAA.',
Av='Avaniah:BAABNQAECoEWAAIHAAcK6hxCDgAdAgAHAAcK6hxCDgAdAgAAAA==.',
Az='Azmodan:BAAANQADCgcIBwAAAA==.Azraelor:BAABNQAECoE5AAMIAAkK9SLeAgByAwAIAAkK9SLeAgByAwAJAAkKxhk3PQBYAgAAAA==.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQAECgUIBQAAAA==.Baep:BAAANQAECgUICgAAAA==.Bandrago:BAABNQAECoEZAAIKAAcKfwjTHQBWAQAKAAcKfwjTHQBWAQAAAA==.Batmeng:BAAANQAECgYIAwAAAA==.',
Bb='Bbirog:BAAANQAECgcIBQABNQAECgcIEwALAAAAAA==.',
Be='Beaulioh:BAAANQAECgcIEwAAAA==.Bekzarn:BAAANQAECgEIAwABNQAECgcIFQACAEAiAA==.Belegmor:BAAANQAECgIIAgABNQAECgUIEQALAAAAAA==.Benfrank:BAABNQAECoEgAAICAAgKqhaLNgAPAgACAAgKqhaLNgAPAgAAAA==.Bernthul:BAAANQAECgcIDwAAAA==.Bethan:BAABNQAECoEUAAIGAAcKtwsYEgBdAQAGAAcKtwsYEgBdAQAAAA==.',
Bl='Blaart:BAABNQAECoEeAAQMAAgKfxfUbgDqAQAMAAcK+RbUbgDqAQANAAIKrxZGTgCIAAAOAAEK4Qf6LQAvAAAAAA==.Blackwaters:BAABNQAECoEdAAMIAAgKwCNSBABHAwAIAAgKwCNSBABHAwAJAAUK0xanlABAAQAAAA==.Blax:BAABNQAECoEaAAMPAAgKjRvcCgD1AQAPAAYKCB7cCgD1AQAQAAYKmhFMsAB2AQAAAA==.Blindcow:BAABNQAECoEnAAIQAAkKvh6eOADLAgAQAAkKvh6eOADLAgAAAA==.Blindhugs:BAAANQAECgcIEQABNQAECgcIFAARABYHAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgYIBgAAAA==.Blùey:BAAANQADCgYIBgABNQAECgkJIgASAHYfAA==.',
Bo='Bodytypebig:BAABNQAECoEvAAITAAkK6xSBDwAqAgATAAkK6xSBDwAqAgAAAA==.Boicrystian:BAAANQAECgQICAAAAA==.Bolillo:BAAANQADCgcIDAABNQAECgcIEwALAAAAAA==.Bomie:BAAANQADCgUIBQAAAA==.Bookitty:BAAANQAECgEIAQAAAA==.Boosty:BAABNQAECoElAAIQAAgKcCAQNADbAgAQAAgKcCAQNADbAgAAAA==.Bossladie:BAAANQADCggICgAAAA==.Bossladìe:BAABNQAECoEsAAIUAAkKpxcwJwC0AgAUAAkKpxcwJwC0AgAAAA==.Boston:BAAANQAECgEIAQAAAA==.',
Br='Brewholic:BAABNQAECoEXAAIVAAgKACM7BgAdAwAVAAgKACM7BgAdAwAAAA==.Brewskie:BAAANQAECgEIAgAAAA==.Bristle:BAABNQAECoEnAAMJAAgKxCCoJQDOAgAJAAgKpSCoJQDOAgAIAAMKDxhYIwDqAAAAAA==.Brommix:BAAANQADCgMIBgAAAA==.Brotem:BAAANQAECggIBwAAAA==.Broxy:BAAANQAECgEIAQAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDwAAAA==.Bullshiitake:BAABNQAECoEWAAIUAAgK+w4oZADGAQAUAAgK+w4oZADGAQAAAA==.',
['Bö']='Bönezone:BAAANQADCgQIBAAAAA==.',
Ca='Calaglin:BAABNQAECoEbAAQMAAgKCxUeeADQAQAMAAcKFhQeeADQAQANAAEKvBtZZABOAAAOAAEKsgGqMQAWAAAAAA==.Calelorian:BAAANQADCgYIDwAAAA==.Catstack:BAAANQAECgEIAQAAAA==.',
Ce='Celdiirn:BAAANQADCggIHwAAAA==.Celesti:BAABNQAECoEZAAISAAYKPxEwxABaAQASAAYKPxEwxABaAQAAAA==.',
Ch='Chiky:BAAANQAECgIIAwAAAA==.Choom:BAAANQAECgYIEQAAAA==.Chubsy:BAAANQAECggIEgAAAA==.Chuckkyd:BAABNQAECoEeAAISAAgKqg9ykADPAQASAAgKqg9ykADPAQAAAA==.',
Cl='Claugh:BAABNQAECoEUAAMWAAgKQxp0NQDHAQAWAAgKFRl0NQDHAQAXAAEKTRTbxgA7AAAAAA==.Cleb:BAABNQAECoEXAAMSAAkKgib3AAD/AwASAAkKgib3AAD/AwAUAAIKeR4b0gCwAAAAAA==.Clocker:BAAANQAECgYIEQAAAA==.Clumbsykoala:BAABNQAECoEUAAICAAYKFQ0JWgBBAQACAAYKFQ0JWgBBAQAAAA==.',
Co='Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAACNQAFFIEUAAIYAAcK9xSVAgBVAgAYAAcK9xSVAgBVAgA1AAQKgSYAAhgACQqrGlsMAM4CABgACQqrGlsMAM4CAAAA.Combatcow:BAABNQAECoEdAAIPAAgK7CK0AwDvAgAPAAgK7CK0AwDvAgAAAA==.Contagion:BAAANQAECggICAAAAA==.Coorona:BAAANQADCgcIDQAAAA==.Cozmic:BAABNQAECoEjAAMFAAkKPCJFQAD2AgAFAAgK2CFFQAD2AgAGAAMKzSLaGQD+AAAAAA==.',
Cr='Craftymidget:BAAANQADCggJCAAAAA==.Crucifixd:BAAANQAECgEIAQAAAA==.Cryptonic:BAAANQAECggICAAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAABNQAECoEmAAIQAAgKLiGDLwDsAgAQAAgKLiGDLwDsAgAAAA==.',
Cu='Curandero:BAABNQAECoEXAAIJAAQKGBDfuADyAAAJAAQKGBDfuADyAAAAAA==.Curie:BAAANQAECgEIAQABNQAECgcIKwAZABkcAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUIBQAAAA==.Dameck:BAABNQAECoEmAAIQAAgK5RIydwAPAgAQAAgK5RIydwAPAgAAAA==.Dankula:BAAANQAECgEIAQAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCggICgABNQAECggIGQAXAPUbAA==.Dasdots:BAAANQAECgYIDAAAAA==.Dasmuro:BAAANQAECgEIAQABNQAECgYIHAADAHEGAA==.Davy:BAAANQADCgYIBgAAAA==.Dazzeler:BAABNQAECoEZAAIXAAgK9RupKgBqAgAXAAgK9RupKgBqAgAAAA==.',
De='Deadeenside:BAAANQADCggIEgABNQAECgcIFwASAC4XAA==.Deanie:BAAANQAECgEIAQAAAA==.Deejaypaulyd:BAABNQAECoEWAAIaAAYKjhHRmQChAQAaAAYKjhHRmQChAQAAAA==.Delver:BAAANQAECgQICQAAAA==.Demongirly:BAAANQABCgQIBAAAAA==.Demonsue:BAAANQAECgEIAQAAAA==.Demorlize:BAAANQADCgQIBAABNQAECgcIFQAZADUQAA==.Denathria:BAABNQAECoEXAAMUAAgK1h7jIgDJAgAUAAgK1h7jIgDJAgASAAEKYRLrYwFBAAAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAACNQAFFIEZAAMRAAcKqxmiAQBxAgARAAcKqxmiAQBxAgAbAAIKPQUlHgC0AAA1AAQKgSMAAhEACQoZJPgGAFkDABEACQoZJPgGAFkDAAAA.Deviourer:BAAANQAECgEIAQAAAA==.Devo:BAAANQAECgEIAQAAAA==.',
Di='Dicspriest:BAAANQAECgEIAwAAAA==.Difflect:BAAANQADCgYIBgABNQAECgEIAQALAAAAAA==.',
Do='Doak:BAABNQAECoErAAMZAAcKGRydEwA8AgAZAAcKGRydEwA8AgAcAAIKignSeAB0AAAAAA==.Doonfist:BAAANQAECgEIAwAAAA==.Dotz:BAACNQAFFIEHAAMNAAMKAxZ8CQCqAAANAAIKbhd8CQCqAAAMAAEKLxNBNgBMAAA1AAQKgSEAAw0ACQrUHpwiAFABAAwABwrRHhlZACoCAA0ABgp0DpwiAFABAAAA.Douchec:BAAANQAECgUICAAAAA==.',
Dr='Draconius:BAAANQADCgYIFQAAAA==.Draenor:BAAANQAECgMICAAAAA==.Dragondilly:BAAANQADCgQIBAAAAA==.Dragonette:BAAANQADCgcIBwABNQAECggIHQAMAGwZAA==.Dragonforce:BAABNQAECoEXAAIKAAcKZxdjFADoAQAKAAcKZxdjFADoAQAAAA==.Dragonhaze:BAABNQAECoEWAAIFAAYKOiCeogAcAgAFAAYKOiCeogAcAgAAAA==.Dragonskull:BAAANQAECgYJBgAAAA==.Drawkcab:BAAANQAECgQIBAAAAA==.Drazentar:BAABNQAECoEcAAIDAAYKcQbdfADfAAADAAYKcQbdfADfAAAAAA==.Dream:BAAANQADCgUICQABNQAECggIGgAdAD0VAA==.Drevox:BAABNQAECoEhAAIXAAgKbRkrPAAKAgAXAAgKbRkrPAAKAgAAAA==.Druiddruid:BAAANQADCgYICQAAAA==.',
Du='Dulgar:BAABNQAECoEnAAIdAAgKDRzmMwBqAgAdAAgKDRzmMwBqAgAAAA==.Dumami:BAAANQAECgEJAQABNQAECgYIAwALAAAAAA==.',
['Dë']='Dëlilah:BAAANQAECgYICAAAAA==.',
Ea='Eaglewarrior:BAAANQADCggIDgAAAA==.',
Ec='Eclipselock:BAAANQAECgEIAQABNQAFFAUIEgABAHgYAA==.',
Eg='Egwaine:BAAANQADCgcICAABNQAECgkJJAACAKwZAA==.',
El='Elind:BAAANQAECgIIAgAAAA==.Elisyum:BAAANQAECgIIAwAAAA==.Elleduff:BAABNQAECoEZAAIeAAcKDQs0MgBOAQAeAAcKDQs0MgBOAQAAAA==.Eloragon:BAAANQAECgEIAQAAAA==.Elyssabeta:BAAANQAECgEIAgAAAA==.Elysstaa:BAABNQAECoEnAAMbAAgKthrVRwApAgAbAAgKthrVRwApAgARAAYKrBIjMAB5AQAAAA==.',
En='Entïty:BAAANQAECgEIAgABNQAECgQIDgALAAAAAA==.',
Eo='Eogden:BAAANQAECgYIDAAAAA==.',
Eq='Equilibria:BAABNQAECoEUAAIRAAYKcxhVKgCtAQARAAYKcxhVKgCtAQAAAA==.',
Er='Erida:BAAANQAECgIJAwAAAA==.Ers:BAAANQADCgYIBgABNQAECgcIEwALAAAAAA==.',
Es='Eskuf:BAAANQADCgMIAwAAAA==.',
Et='Etienne:BAAANQADCgEIAQAAAA==.Etík:BAAANQAECgUICgAAAA==.',
Ev='Evocative:BAACNQAFFIEFAAIKAAIKwhc5CgCWAAAKAAIKwhc5CgCWAAA1AAQKgRwAAgoACQrCHigJAMoCAAoACQrCHigJAMoCAAAA.',
Ex='Exaltso:BAAANQADCgYIDwAAAA==.',
Ey='Eyebright:BAAANQAECgMIBQAAAA==.Eyye:BAAANQADCgQIBgABNQAECgcICgALAAAAAA==.',
Fa='Farns:BAACNQAFFIEPAAMFAAUKjSAkEQDGAQAFAAUKsR0kEQDGAQAGAAIKQRubBQCiAAA1AAQKgSIAAwUACQpUJXkQAIwDAAUACQouJXkQAIwDAAYABAobJj4TAE0BAAAA.Fawndolynn:BAAANQAECgQICwAAAA==.',
Fe='Felinepriest:BAAANQAECgcIEwAAAA==.Felovan:BAAANQAECgEIAQAAAA==.Felsoaked:BAAANQAECgEIAgAAAA==.Felstehr:BAABNQAECoEaAAIMAAcK2g59hACtAQAMAAcK2g59hACtAQAAAA==.Feltotes:BAAANQAECgQIBwAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAABNQAECoEaAAIdAAkKbSCTFgACAwAdAAkKbSCTFgACAwAAAA==.Firebäne:BAABNQAECoEbAAINAAgKjR9rBADWAgANAAgKjR9rBADWAgAAAA==.Fistnor:BAAANQAECgEIAwAAAA==.',
Fl='Flaminghawk:BAACNQAFFIEOAAIFAAUKSRftEQC/AQAFAAUKSRftEQC/AQA1AAQKgR4AAwUABwq0Igx9AGwCAAUABwq0Igx9AGwCAAYAAgoHIIMhAL0AAAAA.',
Fr='Franklin:BAAANQAECgYICQAAAA==.Frankotronic:BAABNQAECoEaAAIFAAgKphJPuADwAQAFAAgKphJPuADwAQAAAA==.Fraynetrain:BAAANQAECgQIBAABNQAECgYICwALAAAAAA==.Frayniac:BAAANQAECgYICwAAAA==.Freakies:BAAANQADCgQIBgAAAA==.Freightfrayn:BAAANQAECgEIAQAAAA==.Freyin:BAABNQAECoEoAAIaAAgK2xqPNACrAgAaAAgK2xqPNACrAgAAAA==.Frie:BAAANQADCgYIBgAAAA==.Frolgar:BAAANQADCgYICAAAAA==.Frostyflakez:BAAANQAECgEJAQAAAA==.',
Fu='Fullclangg:BAACNQAFFIEHAAIUAAMKviRHDgBEAQAUAAMKviRHDgBEAQA1AAQKgRgAAhQACAp3HZksAJoCABQACAp3HZksAJoCAAE1AAUUCAgjABgAcRsA.Fulldracarys:BAACNQAFFIEjAAIYAAgKcRveAADRAgAYAAgKcRveAADRAgA1AAQKgSQAAhgACQrPIhUHACgDABgACQrPIhUHACgDAAAA.Fullgabagool:BAABNQAECoEeAAIbAAkKeB2sHADnAgAbAAkKeB2sHADnAgABNQAFFAgIIwAYAHEbAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAgIIwAYAHEbAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCggIGQAAAA==.Ganster:BAAANQAECgQIBgAAAA==.Gaya:BAAANQADCgYIEAAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAABNQAFFIEIAAIQAAQK/wQ2GgD6AAAQAAQK/wQ2GgD6AAAAAA==.',
Gi='Ginyeng:BAAANQAFFAMIAwAAAA==.',
Gl='Glimpse:BAABNQAECoEXAAIGAAkKyyI7AQB1AwAGAAkKyyI7AQB1AwAAAA==.',
Gn='Gnomebody:BAAANQAECgIIBQAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBgAAAA==.',
Gr='Greenmonsta:BAAANQADCgUIBQAAAA==.Grimknight:BAABNQAECoEtAAISAAkKRyazBQDEAwASAAkKRyazBQDEAwAAAA==.Groovi:BAAANQADCgUIBQAAAA==.',
Gu='Guycow:BAABNQAECoEcAAIUAAkK9R4xGAAHAwAUAAkK9R4xGAAHAwAAAA==.',
Ha='Hambonë:BAACNQAFFIEZAAICAAcKuh/EAQCuAgACAAcKuh/EAQCuAgA1AAQKgSUAAgIACQpvJuEBANkDAAIACQpvJuEBANkDAAAA.Hardballs:BAAANQADCgUIBgAAAA==.Hashbrowns:BAABNQAECoEnAAISAAkKnCM4CwCaAwASAAkKnCM4CwCaAwAAAA==.Havdk:BAAANQAECgIIBQAAAA==.Haxxorwyn:BAAANQAECgcIDQAAAA==.Hazreil:BAABNQAECoEnAAITAAgKAhkVDgBEAgATAAgKAhkVDgBEAgAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIEwAAAA==.Heavenlee:BAABNQAECoEaAAIbAAcKNApUggBWAQAbAAcKNApUggBWAQABNQADCggIEwALAAAAAA==.Hecklefish:BAABNQAECoEmAAMaAAkKiCY6AgDbAwAaAAkKiCY6AgDbAwAfAAIKkhyLWQCZAAAAAA==.Hellik:BAAANQAECgEIAQAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAABNQAECoEhAAIJAAgKMRBkXQDbAQAJAAgKMRBkXQDbAQAAAA==.Highdegrees:BAAANQAECgQIBwAAAA==.Hinatta:BAAANQAECgEIAQABNQAECgcIHAAbANwUAA==.Hitagi:BAAANQAECgYIEwAAAA==.',
Ho='Hole:BAAANQAECgEIBAAAAA==.Hollo:BAAANQAECgMIBQAAAA==.Holyblasts:BAABNQAECoEdAAISAAgKwyNlHwAuAwASAAgKwyNlHwAuAwAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQAECgEIAgABNQAECgEIAwALAAAAAA==.Horsey:BAAANQAECgYIBwABNQAECggIFwAWAOQeAA==.Hownow:BAAANQAECgEIAQAAAA==.',
Hu='Hummingbird:BAAANQAECgQIBgABNQAECggIFwAUANYeAA==.Hungus:BAAANQAECgQICAAAAA==.Hurtszick:BAAANQAECgQIDQAAAA==.',
Hy='Hydrotiger:BAAANQAECgUICAABNQAECgkJLQAIAEIhAA==.',
['Hä']='Härasou:BAAANQADCgYIEwAAAA==.',
Il='Illiturtle:BAABNQAECoEbAAMgAAcKYhpsIAAtAgAgAAcKYhpsIAAtAgAhAAEKRgsALAAwAAAAAA==.',
Im='Imnotthtgood:BAAANQAECgEIAQAAAA==.',
In='Indever:BAAANQAECgEIAgAAAA==.Indigolemon:BAABNQAECoEfAAQCAAgKgBv6KABsAgACAAgK2Bn6KABsAgATAAMKHhyLKgD7AAAiAAEKxwdobQAkAAAAAA==.Inkenhancer:BAABNQAECoEbAAIJAAgKcx5HKAC/AgAJAAgKcx5HKAC/AgAAAA==.Inscissor:BAAANQAECgQIBAABNQAECgUIBQALAAAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Iy='Iyari:BAAANQADCgYIDwAAAA==.',
Ja='Jaffaar:BAAANQADCggICAAAAA==.Jamie:BAABNQAECoEWAAISAAcKxg3prwCGAQASAAcKxg3prwCGAQAAAA==.',
Je='Jeynsa:BAAANQAECgYICAABNQAECgkJJAACAKwZAA==.',
Ji='Jingadingado:BAAANQADCgYIBgAAAA==.',
Jo='Jollyollie:BAAANQADCgQIBQAAAA==.Joppy:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQAECgQIDAAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jë']='Jëf:BAAANQAECgEIAQAAAA==.',
['Jô']='Jôker:BAAANQAECgYIEwAAAA==.',
Ka='Kacho:BAAANQAECgEIAQAAAA==.Kaelara:BAAANQAECggIBgAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kalano:BAAANQADCggICAAAAA==.Kaorii:BAAANQAECgIIAgAAAA==.Kappo:BAAANQAECgYIDgAAAA==.Karryn:BAAANQADCgQIAwAAAA==.Kathorall:BAABNQAECoEZAAIaAAgKAA1vdAD5AQAaAAgKAA1vdAD5AQAAAA==.Kawaiihealer:BAABNQAECoEcAAMbAAcK3BSdZwC0AQAbAAcK3BSdZwC0AQARAAIKzgNwYwBLAAAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIAwAAAA==.Keledril:BAAANQAECgcIBwAAAA==.Kemper:BAABNQAECoEXAAMjAAYK6g3hCACFAQAjAAYK6g3hCACFAQAaAAMKHwpJEwGHAAAAAA==.Kerrs:BAAANQAECgEIBgAAAA==.Kerrz:BAAANQAECgMIBAAAAA==.',
Ki='Kiamonk:BAAANQAECggICAAAAA==.Kiddyl:BAAANQADCgYIFAAAAA==.Kidneypopper:BAAANQADCgcICAABNQAECgkJIwAFADwiAA==.Kievit:BAAANQAECgYICQAAAA==.Kir:BAAANQAECgcIEwABNQAECgcIFwASAC4XAA==.Kittana:BAABNQAECoEfAAIUAAcKWh6kOABlAgAUAAcKWh6kOABlAgAAAA==.Kittyhawke:BAAANQAECggIDgABNQAECggIHwACAIAbAA==.',
Kk='Kkelhus:BAAANQAECgYIDQABNQAECgkJJAAZAMcYAA==.Kkonetica:BAAANQAECgIIAgABNQAECgkJJAAZAMcYAA==.Kkrantuq:BAABNQAECoEkAAIZAAkKxxjvCQDKAgAZAAkKxxjvCQDKAgAAAA==.Kkylar:BAAANQAECgYIDQABNQAECgkJJAAZAMcYAA==.',
Kl='Klariityy:BAABNQAECoEhAAMbAAkKPxIhOgBdAgAbAAkKPxIhOgBdAgARAAEK8A4DcQAtAAAAAA==.Klarity:BAAANQAECgcICgAAAA==.Klarityqt:BAAANQAECgQIBAAAAA==.Klarityx:BAACNQAFFIEKAAIFAAQKewkIJAAmAQAFAAQKewkIJAAmAQA1AAQKgTUAAgUACQrtHscuACQDAAUACQrtHscuACQDAAAA.',
Kn='Knownentity:BAAANQAECgQIDgAAAA==.',
Ko='Koma:BAAANQADCggJCAABNQAFFAcIGAAJADokAA==.Komatos:BAACNQAFFIEYAAIJAAcKOiRkAAD9AgAJAAcKOiRkAAD9AgA1AAQKgSoAAgkACQqMJvsCANIDAAkACQqMJvsCANIDAAAA.Koreantacos:BAAANQADCgcIDQAAAA==.Koronus:BAAANQADCgcIFwAAAA==.',
Kr='Kracklin:BAAANQAECgQIBAAAAA==.',
Ku='Kurisutina:BAAANQAECgQICAAAAA==.',
['Kâ']='Kânamë:BAAANQADCggICAABNQAECgcIIQAXAOgSAA==.',
['Kê']='Kênsêi:BAABNQAECoEhAAMXAAcK6BJfXAB3AQAXAAcKthJfXAB3AQADAAMK6RGhigCzAAAAAA==.',
['Kô']='Kôan:BAAANQAECgcIDwAAAA==.',
La='Lanatec:BAAANQAECgIIBAAAAA==.Largetimmy:BAAANQADCggICQABNQAECgcIEwALAAAAAA==.Lazyshifter:BAAANQAECgEIAQAAAA==.',
Le='Leafyjoe:BAABNQAECoEgAAICAAgKWhrYKABtAgACAAgKWhrYKABtAgAAAA==.Lechencaja:BAAANQADCgYJBgABNQAECgcIEAALAAAAAA==.Led:BAAANQAECgEIAQAAAA==.Legendarybob:BAAANQADCgYJBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAABNQAECoEjAAQXAAgKXgl5cQAqAQAXAAcK/wZ5cQAqAQAWAAYKmgl4UgAaAQADAAcKTwVccwADAQAAAA==.Legö:BAAANQAECggIBwABNQAECggIIwAXAF4JAA==.Leitbur:BAAANQAECggICAAAAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECggIHwAcAAYdAA==.',
Li='Libidine:BAAANQADCgIIAgABNQAECgUIDgALAAAAAA==.Lido:BAAANQAECggIEwAAAA==.Lilcowdk:BAAANQADCgEIAQABNQAECgkJJgANAOgZAA==.Lildeemon:BAABNQAECoEmAAMNAAkK6BkKDgANAgAMAAgKuhbJUgA8AgANAAcKSBgKDgANAgAAAA==.Lilspyro:BAAANQAECgQIBgAAAA==.Lionsinpride:BAAANQADCgYIBgAAAA==.Livathian:BAABNQAECoEdAAISAAgKAQ2DoQCmAQASAAgKAQ2DoQCmAQAAAA==.Lizwiz:BAAANQAECgYICwAAAA==.',
Lo='Lokrah:BAAANQABCgMIBgAAAA==.Lothuial:BAAANQADCgcIBwAAAA==.',
Lu='Lucerubis:BAAANQAECggIDgAAAA==.Lucifiux:BAABNQAECoEXAAQXAAgKjQhVZwBOAQAXAAgKLQdVZwBOAQADAAIKYg31qQBXAAAWAAEKdQY+oAAiAAAAAA==.Lunavel:BAABNQAECoEfAAMSAAcKrhXgrgCJAQASAAYKCxjgrgCJAQAkAAUK2w4KPQDgAAAAAA==.Lurex:BAAANQAECgEIAgAAAA==.',
Ly='Lydo:BAAANQAECggIDAAAAA==.',
Ma='Macaria:BAAANQAECgQIBAAAAA==.Maggette:BAAANQADCgYIBgABNQAECggIHQAMAGwZAA==.Magicdan:BAAANQADCgYICAAAAA==.Malnorr:BAABNQAECoEZAAMMAAgK0RTVbgDqAQAMAAcKOxXVbgDqAQANAAIKhxIJVAB4AAAAAA==.Mandragon:BAAANQADCgUIBQABNQAECgkJHAAUAPUeAA==.Mangol:BAABNQAECoEXAAMSAAgKNyTVGwA+AwASAAgKNyTVGwA+AwAUAAMKGxTnvgDUAAAAAA==.Manudei:BAAANQAECgcIDwAAAA==.Marryg:BAAANQAECgIIAwABNQAECgkJFAAeAF0XAA==.Maryillo:BAACNQAFFIEWAAICAAcKihvaAgB5AgACAAcKihvaAgB5AgA1AAQKgSQAAgIACQpgJZsKAGsDAAIACQpgJZsKAGsDAAAA.Mattdaemon:BAAANQAECgYICwAAAA==.',
Mc='Mcmannis:BAAANQAECgcICAAAAA==.Mcpoltrain:BAAANQAECgYIDgAAAA==.',
Me='Mennil:BAAANQAECgUIDgAAAA==.Mental:BAAANQAECgQIBAABNQAFFAUIEAAgAGoSAA==.Meolater:BAABNQAECoEeAAIYAAcKZx2uFQBDAgAYAAcKZx2uFQBDAgAAAA==.Mesmerise:BAAANQAECgcIDgAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECggIHwAcAAYdAA==.Mindgoblinn:BAABNQAECoEYAAIbAAcKaxYzWgDjAQAbAAcKaxYzWgDjAQAAAA==.Minicookie:BAAANQAECgEIAgAAAA==.Minyaw:BAAANQAECgQICAABNQAECgcIKwAZABkcAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQAECgQICwAAAA==.',
Mm='Mmchocolat:BAAANQAECgUIBgAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEBNQAECoEnAAIjAAgK3R+aAgDuAgAjAAgK3R+aAgDuAgAAAA==.Moolissa:BAAANQAECgYIEwAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgQICQAAAA==.Morbidchaos:BAACNQAFFIEZAAIgAAcKBiRTAADhAgAgAAcKBiRTAADhAgA1AAQKgSYAAyAACQqwIvkIAD0DACAACQqwIvkIAD0DAAEAAgqjGyRnAKgAAAAA.Mordekai:BAAANQAECgEIAgAAAA==.Morkels:BAAANQAECgcIDgABNQAFFAkJIwAlAFckAA==.',
Mu='Muddyshark:BAABNQAECoEWAAMWAAgKxAZyUAAlAQAWAAcKyQZyUAAlAQAXAAYK9AQ0ggDtAAAAAA==.Mukatsuku:BAAANQAECgUICgAAAA==.Muscida:BAAANQAECgMIBgAAAA==.',
My='Mykhawk:BAAANQADCgUICAAAAA==.',
['Mâ']='Mâyüri:BAAANQADCgYIBgABNQAECgcIIQAXAOgSAA==.',
Na='Naeth:BAABNQAECoEkAAISAAgKjx7VTwB9AgASAAgKjx7VTwB9AgAAAA==.Nalrot:BAAANQADCggIDwABNQAECgcIDgALAAAAAA==.Narcine:BAABNQAECoEcAAIaAAkKRh1SHwD+AgAaAAkKRh1SHwD+AgAAAA==.',
Ne='Neciecakes:BAABNQAECoEnAAMUAAgKexeCPgBMAgAUAAgKexeCPgBMAgASAAEK4BAcagE7AAAAAA==.Nee:BAABNQAECoEhAAMdAAkKLhKdSQAQAgAdAAkKLhKdSQAQAgAJAAUKuBB2nQAsAQAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nekus:BAAANQADCgcIBwAAAA==.Nelor:BAABNQAECoEVAAIgAAcK6Q5YLwCkAQAgAAcK6Q5YLwCkAQAAAA==.Nerftitty:BAAANQADCgUIBQAAAA==.Nettles:BAAANQAECgQIBQAAAA==.Neverheal:BAAANQADCgEIAQAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ng='Ngàymai:BAAANQADCgQIBAAAAA==.',
Ni='Nightwatchr:BAAANQAECggIDgAAAA==.Nisona:BAAANQAECgQIBQAAAA==.Nitashal:BAABNQAECoEiAAMYAAkKch22CwDZAgAYAAkKch22CwDZAgAKAAEKoA7GNwA2AAABNQAFFAMIAwALAAAAAA==.',
No='Nokthro:BAAANQADCgYJBgABNQAECgkJLAAKANEfAA==.Noremac:BAAANQAECgEIAQAAAA==.',
Nu='Nubsaiboot:BAAANQAECgUICQABNQAECgcIFwASAC4XAA==.',
Ny='Nythariel:BAAANQADCggIGgAAAA==.',
['Në']='Nëzükõ:BAAANQADCgYIBgABNQAECgcIIQAXAOgSAA==.',
Od='Odi:BAAANQAECgUICAAAAA==.',
Ok='Okiaat:BAAANQAECgYIBwAAAA==.',
Ol='Oliviawildè:BAABNQAECoEeAAMUAAkKPRpaFwAMAwAUAAkKPRpaFwAMAwASAAEKjwJWmQEhAAAAAA==.',
On='Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAgAAAA==.',
Pa='Pakoh:BAABNQAECoEVAAMCAAcKQCIiKwBcAgACAAYKoSQiKwBcAgAiAAYKdRbmLAB/AQAAAA==.Pallyforhire:BAAANQAECgEIAQAAAA==.Panfriedrice:BAAANQAECggICgAAAA==.Pantyblossom:BAABNQAECoEUAAIbAAcKzR6zOABjAgAbAAcKzR6zOABjAgABNQAECggIHQAMAGwZAA==.',
Pe='Peaches:BAAANQAECgQIBwAAAA==.Peewees:BAAANQADCgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAABNQAECoEkAAINAAcKmR8xBwCJAgANAAcKmR8xBwCJAgAAAA==.Peladin:BAAANQAECgEIAQAAAA==.Pelado:BAAANQAECgEIAgAAAA==.Pelito:BAAANQAECgEIAgAAAA==.Pell:BAAANQAECgEIAwAAAA==.Pelo:BAAANQAECgEIAgAAAA==.Pewpewz:BAAANQAECgIIAwABNQAECggIIwAQANUQAA==.',
Ph='Phaeddrus:BAAANQAECgQIBgAAAA==.Phobos:BAABNQAECoEUAAIlAAgKcwhPDABnAQAlAAgKcwhPDABnAQAAAA==.Phogood:BAAANQAECgMIAwAAAA==.Phrix:BAAANQADCgUIBgABNQAECgkJLAAKANEfAA==.',
Pi='Pinecone:BAABNQAECoEbAAICAAkKbSNUFQAGAwACAAkKbSNUFQAGAwAAAA==.',
Pl='Ploppster:BAAANQADCggIDQAAAA==.Plot:BAAANQAECggIEAAAAA==.Plsno:BAAANQADCgIIAgAAAA==.',
Po='Poekimaw:BAAANQAECgEIAQAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAACNQAFFIEHAAISAAMKuiEVDgAvAQASAAMKuiEVDgAvAQA1AAQKgSIAAhIACQq9JakNAIoDABIACQq9JakNAIoDAAAA.Poppinin:BAABNQAECoEYAAISAAcKhxH+owChAQASAAcKhxH+owChAQAAAA==.Potaters:BAAANQAECgEIAQAAAA==.Potshotbot:BAAANQAECgEICAAAAA==.Powerwordhug:BAABNQAECoEUAAQRAAcKFgfiNgBHAQARAAcKFgfiNgBHAQAmAAYKvQjxDwASAQAbAAIKcgID2ABOAAAAAA==.',
Pr='Praedo:BAAANQADCgYJBgAAAA==.Prevaleon:BAAANQAECgEIAQAAAA==.',
Ps='Psychaos:BAAANQAECgcIDwAAAA==.Psychostorm:BAAANQAECgQIBQAAAA==.Psychritic:BAABNQAECoEVAAIFAAgK+xuBfABtAgAFAAgK+xuBfABtAgAAAA==.Psyence:BAAANQADCgcIDgAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purpletotem:BAAANQAECgYIBgAAAA==.Purrsnikitty:BAAANQADCggIEwAAAA==.Pus:BAAANQADCgYIBgABNQAECggIJQAQAHAgAA==.',
Qo='Qookd:BAAANQAECgQIBQAAAA==.',
Qu='Quillmane:BAAANQAECgUIBgABNQAECgkJLAAKANEfAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAABNQAECoEiAAIgAAkKIB2QEADbAgAgAAkKIB2QEADbAgAAAA==.Ragingdeath:BAAANQAECgEIAQAAAA==.Ragingdivine:BAAANQAECgEIAQAAAA==.Rainakamugi:BAAANQAECgQJCAABNQAFFAMIBwAbAB8MAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQAECgQICgAAAA==.Ralphanir:BAABNQAECoEaAAIdAAcKIRLOcwCBAQAdAAcKIRLOcwCBAQAAAA==.Raskreia:BAAANQADCggICQAAAA==.Raygyu:BAAANQADCgQIBAABNQAECgkJHQAaACAfAA==.Rayvoker:BAAANQADCgYJDAABNQAECgkJHQAaACAfAA==.',
Re='Reek:BAAANQAECgYIEwAAAA==.Reignz:BAAANQAECgcIBwAAAA==.Rexari:BAABNQAECoEWAAMmAAUKwh1GCQCtAQAmAAUKwh1GCQCtAQARAAUKZhsiMAB5AQAAAA==.Rezmae:BAAANQAECgEIAgAAAA==.',
Rh='Rhaiordan:BAAANQAECgIIAgAAAA==.',
Ri='Riniedaze:BAAANQADCgUICgAAAA==.',
Ro='Rockandstone:BAACNQAFFIEJAAIUAAUKpwSlDQBSAQAUAAUKpwSlDQBSAQA1AAQKgS4AAhQACQqpFoUxAIQCABQACQqpFoUxAIQCAAAA.Rocki:BAAANQAECgEJAQABNQAFFAMIBwANAAMWAA==.Rooty:BAAANQAECgQICAAAAA==.Roron:BAAANQAECgQIBAAAAA==.',
['Rì']='Rìmûrü:BAAANQADCggICAABNQAECgcIIQAXAOgSAA==.',
Sa='Safetyspork:BAAANQAECgcICgAAAA==.Sagë:BAAANQAECgUIDwAAAA==.Sakonutz:BAABNQAECoEeAAIiAAcK9gw5MABkAQAiAAcK9gw5MABkAQAAAA==.Salsa:BAAANQADCgcIDwAAAA==.Saresh:BAABNQAFFIEGAAIbAAMKBhGUGAD1AAAbAAMKBhGUGAD1AAAAAA==.Sathariel:BAAANQAECgEIAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.',
Sc='Schlee:BAAANQAECgEIAQAAAA==.Screeps:BAAANQAECgEIAwABNQAECgEIAwALAAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAABNQAECoEdAAIMAAgKbBl0RwBfAgAMAAgKbBl0RwBfAgAAAA==.Selceor:BAAANQADCggIDgAAAA==.Sendh:BAAANQAECgYIEAAAAA==.Sermet:BAAANQAECgUIDAABNQAECggIGQAgAHIbAA==.Sermonn:BAAANQAECgQICgAAAA==.Serous:BAAANQAECgYIEgAAAA==.Serwellmet:BAAANQAECgIIAgABNQAECggIGQAgAHIbAA==.Seshin:BAAANQAECggIKQAAAQ==.Set:BAAANQADCggICAABNQAECgkJLAAKANEfAA==.Setal:BAABNQAECoEsAAMKAAkK0R9tBgAOAwAKAAkK0R9tBgAOAwAlAAEKowkjHwA5AAAAAA==.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgcIKwAZABkcAA==.Shammoo:BAAANQAECgMIBQAAAA==.Shawz:BAAANQADCgYIBgAAAA==.Shcho:BAAANQAECgMIBgAAAA==.Sheepe:BAABNQAECoEUAAMPAAYK7xY/DgCoAQAPAAYK7xY/DgCoAQAQAAEK+QM9QQEnAAAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgQIBAAAAA==.Shinyscalp:BAABNQAECoEYAAIQAAkKLCC/IAAnAwAQAAkKLCC/IAAnAwAAAA==.Shkanna:BAAANQAECggICgAAAA==.Shogunz:BAAANQAECgUJBwAAAA==.',
Si='Simaria:BAAANQADCggIFAAAAA==.Sinapaladin:BAABNQAECoEXAAMSAAcKLhfUiADhAQASAAcK2hbUiADhAQAkAAYK6BHXLwA1AQAAAA==.Siomara:BAABNQAECoEaAAMRAAcKyA8+MgBoAQARAAYKQxA+MgBoAQAbAAYKcg/ZgQBYAQAAAA==.Sivanya:BAAANQADCgYJBgAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQAECgEIAwAAAA==.Skrepz:BAAANQAECgEIAQABNQAECgEIAwALAAAAAA==.Skypri:BAAANQAECgEIAwAAAA==.',
Sl='Slabbster:BAAANQAECgQIDgAAAA==.',
Sm='Smooshednewt:BAABNQAECoEtAAIIAAkKQiGEAwBeAwAIAAkKQiGEAwBeAwAAAA==.',
Sn='Sne:BAAANQAECgQIDQAAAA==.Snoop:BAABNQAECoEUAAIFAAgKPQyHwADfAQAFAAgKPQyHwADfAQAAAA==.',
So='Soloa:BAAANQAECgMIBAAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAABNQAECoEkAAICAAkKrBkCHQDGAgACAAkKrBkCHQDGAgAAAA==.Sosneaky:BAAANQADCgMICAAAAA==.Soulfuria:BAAANQAECggIBwAAAA==.',
Sp='Spekk:BAAANQADCgYICgAAAA==.Speknawz:BAABNQAECoEbAAMZAAkKSxauDwBwAgAZAAkKFxWuDwBwAgAcAAMK2xkiYgDbAAAAAA==.Splatzill:BAAANQADCgIIAgABNQAECgkJLwAQALUZAA==.Spoiledangel:BAABNQAECoEZAAIbAAYKbhhXbACiAQAbAAYKbhhXbACiAQAAAA==.Spoonhat:BAAANQADCgcICwABNQAECgcICgALAAAAAA==.Springz:BAAANQAECgUIDQAAAA==.',
Sr='Srwednesday:BAAANQAECgIIAQAAAA==.',
St='Staggering:BAABNQAECoEaAAIJAAgKrhcARAA6AgAJAAgKrhcARAA6AgAAAA==.Starryniight:BAAANQAECgUIEAAAAA==.Stephsux:BAABNQAECoEUAAINAAcKmBMsEQDlAQANAAcKmBMsEQDlAQAAAA==.Stickers:BAAANQAECgMJBAAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgYICQAAAA==.Suika:BAAANQAECgQIBAAAAA==.Supanova:BAABNQAECoEfAAMRAAkKKhpoFACgAgARAAgKEhxoFACgAgAbAAQKexhvjQAzAQABNQAECgkJLQAIAEIhAA==.Surwick:BAABNQAECoEUAAISAAgKMweTvQBoAQASAAgKMweTvQBoAQAAAA==.',
Sv='Svelus:BAACNQAFFIEUAAISAAYK/iQ2AQCJAgASAAYK/iQ2AQCJAgA1AAQKgSYAAhIACQohJo0MAJEDABIACQohJo0MAJEDAAAA.',
Sw='Swingin:BAABNQAECoEWAAIkAAYKThJqLgBAAQAkAAYKThJqLgBAAQAAAA==.',
Sy='Sycophancy:BAAANQAECgEIAgABNQAECgkJLQAIAEIhAA==.Synaptichole:BAAANQAECgQICgAAAA==.Syroka:BAAANQAECgEIAQAAAA==.',
Ta='Tachealz:BAABNQAECoEaAAMdAAgKPRWoTQABAgAdAAgKPRWoTQABAgAIAAQKbwRbJQDKAAAAAA==.Talos:BAAANQAECgEIAwAAAA==.Tanurhide:BAAANQADCgQIBAAAAA==.Taropie:BAAANQADCggICQAAAA==.Tartan:BAABNQAFFIEFAAIfAAIK8B5nFQCwAAAfAAIK8B5nFQCwAAAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.Taylorswif:BAAANQADCgEIAQABNQAECgkJIgAGAHkhAA==.',
Te='Tearal:BAAANQADCgEIAQAAAA==.Techi:BAAANQADCgIIAgAAAA==.Teewat:BAAANQADCgUIBQAAAA==.Temres:BAABNQAECoEZAAQgAAgKchuiFwCIAgAgAAgKrhqiFwCIAgABAAUKERzYPQCWAQAhAAEKFx0rJgBUAAAAAA==.Tendermulva:BAABNQAECoEXAAIOAAgKxAhEDAB0AQAOAAgKxAhEDAB0AQAAAA==.Terekk:BAAANQADCggIHwAAAA==.Teshtara:BAAANQAECgQIBgABNQAECgkJJAACAKwZAA==.',
Th='Theod:BAAANQAECgEIAQAAAA==.Thesauce:BAACNQAFFIEQAAMeAAUKdB/KBQCEAQAeAAQKYSDKBQCEAQAEAAQKNBqLAwBSAQA1AAQKgSIAAx4ACQodJQUGAF8DAB4ACQrOJAUGAF8DAAQABwoSIzwHAKwCAAAA.Thiaw:BAAANQAECgMIBwAAAA==.Thimo:BAAANQADCgEIAQABNQADCggICQALAAAAAA==.Thrikal:BAABNQAECoEnAAIBAAgKZRI1MQDvAQABAAgKZRI1MQDvAQAAAA==.Thugd:BAAANQAECgEIAQABNQAECggIFAAFAD0MAA==.',
To='Tomsmg:BAABNQAECoEiAAMFAAkKgBnTbQCNAgAFAAkKgBnTbQCNAgAGAAEKdAdpRgAqAAAAAA==.Toofs:BAAANQAECgcIEwAAAA==.Toxifay:BAAANQAECgYIEAAAAA==.',
Tr='Traell:BAAANQADCgYIDAAAAA==.Trd:BAAANQABCggICgAAAA==.Treehuggles:BAAANQAECgQIBwABNQAECgcIFAARABYHAA==.Trollbanæ:BAAANQADCgUIBQAAAA==.Trousersnake:BAAANQADCggICAABNQAECggIFwAVAAAjAA==.Truedat:BAAANQADCgQIBwAAAA==.',
['Tì']='Tìõ:BAAANQAECgEIAQABNQAECgcIIQAXAOgSAA==.',
Ug='Ughtismo:BAAANQADCgUJBQAAAA==.',
Un='Undeadban:BAAANQAECgEIAQAAAA==.',
Us='Usagiknight:BAAANQAECgcIEQAAAA==.Ushii:BAAANQAECgQIEAAAAA==.',
Va='Valdemort:BAAANQADCgQIBAABNQAECgcICgALAAAAAA==.Valei:BAAANQAECgQIBQAAAA==.Vampirevic:BAAANQAECgEIAQAAAA==.',
Ve='Veganforlife:BAAANQADCgIIAwAAAA==.',
Vi='Vinda:BAABNQAECoEnAAIRAAgKWhlWHAA+AgARAAgKWhlWHAA+AgAAAA==.Vivixia:BAAANQAECgYIDgAAAA==.',
Vo='Volgrath:BAAANQAECggICAAAAA==.Voodoolock:BAAANQAECgQIDgABNQAECggIGgAdAD0VAA==.',
Wa='Walkingboot:BAAANQADCgQIBAAAAA==.Wallo:BAABNQAECoEjAAIQAAgK1RCxhgDmAQAQAAgK1RCxhgDmAQAAAA==.Wardin:BAAANQAECgEIAgAAAA==.Washedbolt:BAAANQAECgEIAgAAAA==.Washedpyro:BAAANQAECgIIBQAAAA==.Washedzebu:BAABNQAECoEbAAMcAAcKrRmULQD6AQAcAAcKrRmULQD6AQAZAAUKVw4lMQATAQAAAA==.Watsatotem:BAAANQAECgYIBQAAAA==.Wayfairkid:BAAANQAECgEIAQAAAA==.',
We='Weeb:BAACNQAFFIEjAAIlAAkKVyQKAADXAwAlAAkKVyQKAADXAwA1AAQKgSEAAyUACQqtJuEAAKIDACUACQqtJuEAAKIDAAoACAqQGkcTAPsBAAAA.Werken:BAAANQAECgIIAwAAAA==.',
Wh='Whiterabbitt:BAAANQAECgEIAQAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQAECgEIAwAAAA==.Wilmabfiymr:BAAANQAECgEIAgAAAA==.',
Wo='Woa:BAAANQADCggIEgAAAA==.Woofwoofwoof:BAAANQAECgQICwAAAA==.',
Wr='Writhe:BAAANQABCgQICAABNQAFFAcIFwAEAIYiAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Xq='Xquori:BAAANQADCggICwAAAA==.',
Ye='Yeeloow:BAAANQADCgYIDQAAAA==.',
Ys='Yshaarj:BAAANQADCggIEgAAAA==.',
Yu='Yulok:BAACNQAFFIEXAAMEAAcKhiImAAC7AgAEAAcKayImAAC7AgAeAAYKkRPbAwDfAQA1AAQKgSIAAwQACQqVJqAAANkDAAQACQqVJqAAANkDAB4AAwp3IzA1ADQBAAAA.Yuukí:BAAANQADCggICAABNQAECgkJIgASAHYfAA==.',
['Yú']='Yúúki:BAABNQAECoEZAAIDAAgKlh6zHACyAgADAAgKlh6zHACyAgABNQAECgkJIgASAHYfAA==.',
Za='Zaberra:BAABNQAECoEfAAIOAAgKmBaxBQBAAgAOAAgKmBaxBQBAAgABNQAECgkJJAACAKwZAA==.Zanarkand:BAABNQAECoEVAAISAAYKdAiV4AAgAQASAAYKdAiV4AAgAQAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zerofort:BAAANQAECgYIBgAAAA==.Zexexe:BAAANQAECgcIDgABNQAFFAcIGQACALofAA==.',
Zi='Zibroth:BAABNQAECoEbAAMiAAgKAREnJADWAQAiAAgKAREnJADWAQACAAIKSAk4jwBkAAAAAA==.Zieg:BAAANQAECgUIBQAAAA==.Zina:BAAANQAECgIIAwAAAA==.',
['Áo']='Áodh:BAAANQADCggIEAAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQAECgUIDAAAAA==.',
['Ýu']='Ýuuki:BAABNQAECoEiAAISAAkKdh81NwDQAgASAAkKdh81NwDQAgAAAA==.',
['ßr']='ßrß:BAAANQAECgYICgABNQAECggIJQAQAHAgAA==.',
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
