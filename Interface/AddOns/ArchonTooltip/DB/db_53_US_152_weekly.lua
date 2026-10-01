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

local lookup = {'DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Priest-Shadow','Priest-Holy','DemonHunter-Vengeance','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Evoker-Preservation','Warrior-Arms','Shaman-Enhancement','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Paladin-Protection','Warlock-Demonology','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Rogue-Assassination','DemonHunter-Devourer','Priest-Discipline','Druid-Balance','Warrior-Fury','Warlock-Affliction','Druid-Feral','Druid-Restoration','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaylasecura:BAABNQAECoEhAAIBAAkKYx2QDgD+AgABAAkKYx2QDgD+AgAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAcIGAACAIUdAA==.Absinth:BAABNQAECoEWAAMDAAgKLAwWVABeAQADAAcKGw0WVABeAQAEAAEKpgVJjAAmAAAAAA==.',
Ai='Aidaric:BAAANQADCgUJBQAAAA==.Airfriend:BAABNQAECoElAAMFAAkKZQqlWwCoAQAFAAkKZQqlWwCoAQAGAAUKXhvMcQB2AQAAAA==.',
Al='Alder:BAAANQAECgQIBAAAAA==.Alphard:BAABNQAECoEZAAIHAAgKSB2GCwCiAgAHAAgKSB2GCwCiAgAAAA==.',
An='Anelowyn:BAABNQAECoEZAAMIAAgK2BD8KgB8AQAIAAcKvg38KgB8AQAJAAcKtwZ5cQBaAQAAAA==.Angrychicken:BAAANQADCgMIAwAAAA==.',
Ap='Apocal:BAACNQAFFIEHAAIKAAUKGRTOAAB3AQAKAAUKGRTOAAB3AQA1AAQKgSEAAgoACQprImkBAHIDAAoACQprImkBAHIDAAAA.',
Ar='Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAAANQAECgIIAgAAAA==.Asmozaps:BAAANQAECgYIDwAAAA==.',
Az='Aziel:BAAANQAECgcIEgAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAAANQAECgcIEgAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQADCgYICgAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAYIEwAKAMweAA==.Billiards:BAAANQADCggICAABNQAECggIGgALALMUAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABANcFAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECoEdAAIMAAgKehr2SwBiAgAMAAgKehr2SwBiAgAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAABNQAECoEfAAINAAcKFgtqFABTAQANAAcKFgtqFABTAQAAAA==.Bownir:BAAANQAECgUICwAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAABNQAECoEbAAMOAAgKrxKJHwDaAQAOAAgKrxKJHwDaAQAPAAMKKBAmLQCwAAAAAA==.',
Bu='Bubonic:BAAANQAECgUIDgAAAA==.Buenasalud:BAAANQAECgQICAAAAA==.',
Ca='Catopriest:BAAANQAECgQIBAABNQAECggIIwAQAEwQAA==.Caylea:BAACNQAFFIEJAAIRAAUK3Q8zCwCWAQARAAUK3Q8zCwCWAQA1AAQKgSIAAhEACQrYHawqAOUCABEACQrYHawqAOUCAAAA.',
Ch='Chalis:BAAANQAECgYIEQAAAA==.',
Cl='Clamsquirter:BAABNQAECoEUAAMFAAcKTh1tNgBAAgAFAAcKTh1tNgBAAgASAAIKtQm7JQB3AAAAAA==.Clanis:BAAANQADCgIIAgABNQAFFAQICAATABwZAA==.',
Co='Coldhwip:BAABNQAECoEfAAMUAAgKARiEDwBoAQALAAcKjBeLnwD7AQAUAAUK9xSEDwBoAQAAAA==.',
Cr='Crash:BAABNQAECoEjAAIRAAkK6xpGPwCTAgARAAkK6xpGPwCTAgAAAA==.Crtaker:BAAANQAECgcICAAAAA==.Crysis:BAABNQAECoEfAAIVAAgKuReCDAAYAgAVAAgKuReCDAAYAgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgQJBwAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECoEZAAMMAAgKUR5NOwCdAgAMAAgKUR5NOwCdAgAWAAQKWA40PwClAAAAAA==.Dagda:BAAANQAECgIIAgAAAA==.Danye:BAAANQAECgIJAwAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.',
De='Decease:BAAANQAECgQIBAABNQAECgkJHwAXAHojAA==.Delium:BAACNQAFFIELAAILAAUK3RGjEgCRAQALAAUK3RGjEgCRAQA1AAQKgSEAAgsACQozIqEoACgDAAsACQozIqEoACgDAAAA.Demonmommy:BAAANQAECgUIBQAAAA==.Deäthrose:BAABNQAECoEjAAMGAAgKJxBVTgDuAQAGAAgKJxBVTgDuAQAFAAcKxgmyfQA8AQAAAA==.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQADCgQIBgAAAA==.',
Do='Doadin:BAABNQAECoEdAAIYAAgKdBbiOQA/AgAYAAgKdBbiOQA/AgAAAA==.Doominatrix:BAABNQAECoEeAAIXAAcKthKDaQDLAQAXAAcKthKDaQDLAQAAAA==.Dotem:BAAANQADCgYICgAAAA==.',
Dr='Draggum:BAAANQADCggICAABNQAECgQICQAZAAAAAA==.Dreadmagey:BAAANQADCgEIAQABNQADCgYIDAAZAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAAANQAECgcIDQAAAA==.',
Du='Dunktars:BAABNQAECoEZAAIRAAgK9x0RRQB/AgARAAgK9x0RRQB/AgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQADCggIFgABNQAECggIGgALALMUAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAZAAAAAA==.Elisha:BAABNQAECoE9AAIMAAgKThH0cwDnAQAMAAgKThH0cwDnAQAAAA==.',
Er='Erebostro:BAABNQAECoEZAAIaAAgK/xY2QQBeAgAaAAgK/xY2QQBeAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQICAAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAABNQAECoEiAAISAAgKdx5ZCADGAgASAAgKdx5ZCADGAgAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECoElAAMXAAkKuCFgKQCoAgAXAAcKeyJgKQCoAgACAAIKDR/VQgCkAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAFFAIIAgAZAAAAAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAAANQAECgUIEgAAAA==.Gale:BAAANQADCgYIBwABNQAECgUIDgAZAAAAAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECgcICAAAAA==.',
Gh='Ghostfreak:BAABNQAECoEaAAIbAAgK3xWWHQA6AgAbAAgK3xWWHQA6AgAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAYIEQAMAAMhAA==.',
Go='Gobø:BAAANQADCgEIAQAAAA==.Gooby:BAAANQAECgUICgAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAAANQAECgQICQAAAA==.Haranjer:BAABNQAECoEWAAIOAAgKARYAGgAbAgAOAAgKARYAGgAbAgAAAA==.',
He='Hefferhumper:BAAANQAECgYIEQAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAUIDwALAG8eAA==.Homslam:BAABNQAECoEQAAMRAAgKMBzhYAAjAgARAAcKwxfhYAAjAgAVAAQKpRoNHAAbAQABNQAFFAUIDwALAG8eAA==.Homsorc:BAACNQAFFIEPAAMLAAUKbx5pCgDkAQALAAUKbx5pCgDkAQAUAAEK1BwMCABbAAA1AAQKgSQAAgsACQojJoUCAN8DAAsACQojJoUCAN8DAAAA.Homstab:BAABNQAECoEcAAMHAAkKih95DgByAgAHAAcK/B15DgByAgAbAAIK+SQyUgDcAAABNQAFFAUIDwALAG8eAA==.Homtard:BAAANQAECgQIBAABNQAFFAUIDwALAG8eAA==.Homtotem:BAAANQADCggICAABNQAFFAUIDwALAG8eAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECoEbAAIYAAgKUBE5TgDtAQAYAAgKUBE5TgDtAQAAAA==.',
Ic='Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAQICAATABwZAA==.',
Il='Illiandray:BAABNQAECoEXAAICAAcKahlmDAAdAgACAAcKahlmDAAdAgAAAA==.',
In='Insomniac:BAABNQAECoEYAAIcAAgK4yJfCQApAwAcAAgK4yJfCQApAwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUICwAAAA==.Jake:BAAANQAECgQIBAAAAA==.Jangaballs:BAAANQAECgUICwAAAA==.Jawndie:BAABNQAECoEZAAMPAAgKRBrRDQBhAgAPAAgKRBrRDQBhAgANAAEKOQkBKwAjAAAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgEJAQABNQAECggIHgAdAGIeAA==.',
Ka='Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECoEiAAIEAAkKvCEsBwBMAwAEAAkKvCEsBwBMAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAAANQAECgUICwAAAA==.Kestra:BAABNQAECoEfAAIPAAgKdQapHgBJAQAPAAgKdQapHgBJAQAAAA==.',
Ki='Kittysprigg:BAAANQAECgYICwAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFIEIAAITAAQKHBlRCgBJAQATAAQKHBlRCgBJAQA1AAQKgR8AAhMACArhIe8SAKECABMACArhIe8SAKECAAAA.',
Kw='Kwickin:BAAANQAECgEIAQABNQAECgQICQAZAAAAAA==.',
Ky='Kyreen:BAAANQAECgUICwAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgUIEgAZAAAAAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAABNQAECoEiAAILAAgKIRbYjAAlAgALAAgKIRbYjAAlAgAAAA==.',
Lu='Lukafox:BAAANQAECgUIDAAAAA==.Lunastarvale:BAAANQAECgYIDwAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECoEfAAMFAAgKriLEEgAHAwAFAAgKriLEEgAHAwAGAAYK0AaskwAbAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAAANQAECgcIEwAAAA==.Malefisico:BAAANQAECgcIDwAAAA==.Mardríft:BAABNQAECoEgAAIeAAkKDxznFgDlAgAeAAkKDxznFgDlAgAAAA==.Marero:BAAANQADCgYICQAAAA==.Martyr:BAAANQAECgcIEwAAAA==.Mazga:BAABNQAECoEXAAIFAAcKQg7XcABhAQAFAAcKQg7XcABhAQAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECoEiAAIPAAgKUhC7FQDJAQAPAAgKUhC7FQDJAQAAAA==.Monstermayi:BAABNQAECoEfAAMfAAcKMhXoCQDkAQAfAAcKMhXoCQDkAQARAAIK8gve/QBwAAAAAA==.Mooknight:BAABNQAECoEZAAIDAAgKdQnNTwBxAQADAAgKdQnNTwBxAQAAAA==.Morgoth:BAAANQAECgQIDwAAAA==.Morteesha:BAAANQABCgQIBAABNQAECggIGQAPAEQaAA==.',
Mu='Muggy:BAABNQAECoEaAAIbAAgKtRHXIAAfAgAbAAgKtRHXIAAfAgAAAA==.',
My='Myrothar:BAAANQADCgQIBAAAAA==.Mytastical:BAAANQAECgIIBQAAAA==.',
['Må']='Måzikeen:BAAANQADCgMIAwABNQAECgEIAQAZAAAAAA==.',
Na='Najwah:BAAANQAECggIEgAAAA==.Namalis:BAABNQAECoEfAAMXAAkKeiOPEQAhAwAXAAgKzyOPEQAhAwACAAMKyRa0NgDSAAAAAA==.Nanielito:BAAANQAECgcIDgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECggIGgALALMUAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAAANQAECgcIDwAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAAANQAECgUIDwABNQAECggIIAAJAKgVAA==.Nosliw:BAAANQADCgYICwAAAA==.Noxilis:BAAANQAECgQICAAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgUIBgABNQAECgcIBwAZAAAAAA==.',
Om='Omegá:BAAANQAECgcICwABNQAECggIFgADACwMAA==.',
Op='Optìmusprìme:BAAANQAECgcIEgAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Pandalock:BAAANQAECgYIDgAAAA==.Pandemic:BAAANQAECgUICgAAAA==.Papa:BAABNQAECoEeAAQCAAgKXhZ5JwAmAQACAAQKshZ5JwAmAQAXAAQKmxQHrAAVAQAgAAQKvw8rEAD9AAAAAA==.Pawfu:BAABNQAECoEaAAQOAAgKFhOnIgC1AQAOAAcKcBSnIgC1AQAPAAYK3QvMIgAWAQANAAIKmAlnIgBtAAAAAA==.',
Pe='Penywize:BAAANQAECgYIEQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIBAAAAA==.',
Po='Pockets:BAABNQAECoEaAAILAAgKsxT7hwAxAgALAAgKsxT7hwAxAgAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECoEeAAIdAAgKYh5fAgDOAgAdAAgKYh5fAgDOAgAAAA==.',
Pu='Purge:BAAANQAECgIIBAAAAA==.',
Qr='Qrazi:BAABNQAECoEaAAIGAAgKjBKbRwAJAgAGAAgKjBKbRwAJAgAAAA==.',
Qu='Quick:BAAANQAECgQICQAAAA==.',
Ra='Ratha:BAABNQAECoEiAAIWAAgKhiK0BwD2AgAWAAgKhiK0BwD2AgAAAA==.Ravincible:BAAANQADCggIFgAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFIEVAAMHAAcKvx/PAgDzAQAHAAUKRx7PAgDzAQAbAAMKtyGGBgAfAQA1AAQKgSMAAwcACQrYJeMEAC8DAAcACAr6JeMEAC8DABsABQpMIa8tALwBAAAA.Rokkgar:BAAANQAECgUIDAAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECggIEQAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAAANQAECgYIDgAAAA==.',
Sc='Scared:BAACNQAFFIEKAAIJAAUK0QkgCwCMAQAJAAUK0QkgCwCMAQA1AAQKgTgAAgkACQoCH7AKAEoDAAkACQoCH7AKAEoDAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECoEeAAQhAAcKQRsuCwASAgAhAAYKKR4uCwASAgAiAAcKQBXwIADGAQAjAAIKHQvONwBRAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAAAAA==.Shmadu:BAAANQAECggIEQAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgEIAQAAAA==.',
So='Soola:BAAANQADCggICAABNQAECggIIgAWAIYiAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQAECgIIAgAAAA==.',
Su='Surrëal:BAABNQAECoEbAAIBAAgK1wVrRwAYAQABAAgK1wVrRwAYAQAAAA==.',
Sw='Sweetmask:BAAANQAECgMIAwAAAA==.',
Sy='Sybela:BAAANQABCgYIDAABNQAECgkJHQAJAGUaAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECoEZAAIUAAgKbhzXBACPAgAUAAgKbhzXBACPAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgkJIAAGAKwdAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgkJIAAGAKwdAA==.Tanidgetotem:BAABNQAECoEgAAIGAAkKrB1rGgD+AgAGAAkKrB1rGgD+AgAAAA==.',
Te='Teias:BAABNQAECoEgAAMJAAgKqBWTTwDfAQAJAAgKqBWTTwDfAQAIAAEKRhzHWABKAAAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAECggIIAAJAKgVAA==.',
To='Torvald:BAAANQADCggICAABNQADCgYICwAZAAAAAA==.',
Tr='Tricko:BAABNQAECoEXAAIaAAcKkhwwRABUAgAaAAcKkhwwRABUAgAAAA==.Trickshots:BAAANQADCgMIAwABNQAECggIGgALALMUAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECoEYAAILAAcKrxM7swDQAQALAAcKrxM7swDQAQAAAA==.Trollzy:BAABNQAECoEZAAMSAAgKORS7DQBSAgASAAgKORS7DQBSAgAFAAEKxQE2+QAjAAAAAA==.Trunkmonkey:BAABNQAECoEZAAIXAAcK+BbdWQD8AQAXAAcK+BbdWQD8AQAAAA==.Trunky:BAAANQADCgMJBgAAAA==.',
Ts='Tsaagan:BAABNQAECoEhAAIXAAgKjiBFJwCxAgAXAAgKjiBFJwCxAgAAAA==.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECggIHwAVALkXAA==.',
Va='Valica:BAAANQADCgIIAQAAAA==.Valiithria:BAAANQADCgYIEwAAAA==.Valkyruid:BAAANQAFFAEIAQAAAA==.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wa='Waywatcher:BAAANQAECgQICAAAAA==.',
Wh='Whiilow:BAAANQAECgUICwAAAA==.',
Wu='Wullgan:BAAANQAECgcIEAAAAA==.',
Xe='Xencure:BAAANQAECgYICwAAAA==.Xerk:BAAANQAECgcIBwAAAA==.',
Xy='Xyrna:BAABNQAECoEXAAIkAAgKXxzMAgDHAgAkAAgKXxzMAgDHAgABNQAECggIIgAWAIYiAA==.',
Ya='Yareli:BAAANQAECgYIEwAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAAANQAECgYIDwAAAA==.',
Ze='Zeleck:BAAANQAECgUICQAAAA==.Zeno:BAACNQAFFIERAAIMAAYKAyFHAQBcAgAMAAYKAyFHAQBcAgA1AAQKgSUAAgwACQqwJaIJAJkDAAwACQqwJaIJAJkDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAAANQAECgUIDAABNQAECgUIDAAZAAAAAA==.',
Zi='Zinbar:BAAANQAECgUJCQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECggIIgALACEWAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAAANQAECgUIDgAAAA==.',
['Çl']='Çloud:BAAANQAECgIIAwAAAA==.',
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
