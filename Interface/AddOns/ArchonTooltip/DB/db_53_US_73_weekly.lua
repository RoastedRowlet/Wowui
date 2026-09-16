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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Druid-Guardian','Evoker-Preservation','Priest-Shadow','Evoker-Devastation','Mage-Frost','Paladin-Holy','Priest-Holy','Druid-Balance','Hunter-BeastMastery','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Devourer','Evoker-Augmentation','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-09-15',data={Ah='Ahpuch:BAAANQAECgUICwAAAA==.',
Ai='Aidasul:BAAANQAECgMIAwAAAA==.',
Al='Aldesca:BAAANQAECgMIAwAAAA==.',
An='Ancile:BAAANQADCgIIAgAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgYIBwAAAA==.',
Ar='Armstrõng:BAAANQAECgIIAgAAAA==.',
As='Ashaxxi:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.Ashpaw:BAAANQAECgcIEwAAAA==.Aspen:BAAANQAECgEIAQAAAA==.',
At='Atcjedi:BAAANQAECgQIBgAAAA==.Atmospherewr:BAAANQAECggIBwABNQAFFAUICQACAGMfAA==.Atmospherez:BAACNQAFFIEJAAICAAUJYx8pAwADAgACAAUJYx8pAwADAgA1AAQKgR8AAgIACQmyJeQJAI8DAAIACQmyJeQJAI8DAAAA.',
Av='Avaniah:BAAANQAECgUICwAAAA==.',
Az='Azmodan:BAAANQADCgcIBwAAAA==.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQADCggIFAAAAA==.Baep:BAAANQAECgQIBAAAAA==.Bandrago:BAAANQAECgMIBQAAAA==.',
Be='Beaulioh:BAAANQAECgMIBAAAAA==.Bekzarn:BAAANQAECgEIAQABNQAECgYIDgABAAAAAA==.Benfrank:BAAANQAECgYICQAAAA==.Bernthul:BAAANQAECgIIAwAAAA==.Bethan:BAAANQAECgQIBQAAAA==.',
Bl='Blaart:BAABNQAECoEYAAQDAAgJRRfDLgAeAgADAAcJ5BbDLgAeAgAEAAIJDhYhQACJAAAFAAEJ4QcnHgAzAAAAAA==.Blackwaters:BAAANQAECgQICQAAAA==.Blax:BAAANQAECgQIBAAAAA==.Blindcow:BAAANQAECgcIEgAAAA==.Blindhugs:BAAANQAECgUICgAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgYIBQAAAA==.Blùey:BAAANQADCgYIBgABNQAECggIGgAGAFcfAA==.',
Bo='Bodytypebig:BAABNQAECoEcAAIHAAgJkBCBCQDHAQAHAAgJkBCBCQDHAQAAAA==.Boicrystian:BAAANQADCgUIDQAAAA==.Bolillo:BAAANQADCgcIDAABNQAECgMIBAABAAAAAA==.Bomie:BAAANQADCgUIBQAAAA==.Bookitty:BAAANQADCggIGAAAAA==.Boosty:BAAANQAECgYIDgAAAA==.Bossladìe:BAAANQAECgYIDwAAAA==.Boston:BAAANQADCgUIBQAAAA==.',
Br='Brewholic:BAAANQAECgIIAgAAAA==.Bristle:BAAANQAECgYIDgAAAA==.Brommix:BAAANQADCgMIBgAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDgAAAA==.Bullshiitake:BAAANQAECgYIEQAAAA==.',
Ca='Calaglin:BAAANQAECgYIDwAAAA==.Calelorian:BAAANQADCgQIBAAAAA==.Catstack:BAAANQADCgcIFAAAAA==.',
Ce='Celdiirn:BAAANQADCgUIBQAAAA==.Celesti:BAAANQAECgUIDQAAAA==.',
Ch='Chiky:BAAANQAECgIIAwAAAA==.Choom:BAAANQADCgUICgAAAA==.Chubsy:BAAANQAECggICAAAAA==.Chuckkyd:BAAANQAECgQICQAAAA==.',
Cl='Claugh:BAAANQAECggIDwAAAA==.Cleb:BAAANQAECgcICgAAAA==.Clocker:BAAANQAECgQIBAAAAA==.Clumbsykoala:BAAANQAECgMIBQAAAA==.',
Co='Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAACNQAFFIEKAAIIAAYJFA3FAQDyAQAIAAYJFA3FAQDyAQA1AAQKgRoAAggACQn8EWINAFQCAAgACQn8EWINAFQCAAAA.Combatcow:BAAANQAECgcIEgAAAA==.Contagion:BAAANQAECggICAAAAA==.Cozmic:BAAANQAECgYIDwAAAA==.',
Cr='Craftymidget:BAAANQADCggICAAAAA==.Crucifixd:BAAANQAECgEIAQAAAA==.Cryptonic:BAAANQAECggICAAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAAANQAECgUICwAAAA==.',
Cu='Curandero:BAAANQAECgQIDgAAAA==.Curie:BAAANQAECgEIAQABNQAECgYIEwABAAAAAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUIBQAAAA==.Dameck:BAAANQAECgYIDgAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCggICgABNQAECgQIBwABAAAAAA==.Dasdots:BAAANQADCggIFwAAAA==.Dazzeler:BAAANQAECgQIBwAAAA==.',
De='Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAAANQAECgQICQAAAA==.Delver:BAAANQAECgQICQAAAA==.Demongirly:BAAANQABCgQIBAAAAA==.Denathria:BAAANQAECgUICwAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAACNQAFFIEKAAIJAAUJTRg6AQDTAQAJAAUJTRg6AQDTAQA1AAQKgRwAAgkACQk1Ik8DAIYDAAkACQk1Ik8DAIYDAAAA.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.Difflect:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Do='Doak:BAAANQAECgYIEwAAAA==.Doonfist:BAAANQABCggIDgAAAA==.Dottie:BAAANQADCggIGAAAAA==.Dotz:BAABNQAECoEbAAMDAAkJox2kJgBKAgADAAcJSR2kJgBKAgAEAAYJdA7gGQByAQAAAA==.Douchec:BAAANQADCgIIAgAAAA==.',
Dr='Draconius:BAAANQADCgQICgAAAA==.Draenor:BAAANQAECgEIAQAAAA==.Dragonforce:BAAANQAECgMIBAAAAA==.Dragonhaze:BAAANQAECgMIBQAAAA==.Dragonskull:BAAANQADCggICgAAAA==.Drazentar:BAAANQAECgUIBwAAAA==.Dream:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Drevox:BAAANQAECgUICQAAAA==.Druiddruid:BAAANQADCgYICQAAAA==.',
Du='Dulgar:BAAANQAECgYIDgAAAA==.Dumami:BAAANQADCgIIAgAAAA==.',
['Dë']='Dëlilah:BAAANQADCgcICQAAAA==.',
Ea='Eaglewarrior:BAAANQADCggIDgAAAA==.',
El='Elleduff:BAAANQAECgMIBQAAAA==.Elyssabeta:BAAANQADCgQIBAAAAA==.Elysstaa:BAAANQAECgYIDgAAAA==.',
En='Entïty:BAAANQADCgcIDgABNQAECgEIAQABAAAAAA==.',
Eo='Eogden:BAAANQAECgYICgAAAA==.',
Eq='Equilibria:BAAANQAECgMIAwAAAA==.',
Er='Erida:BAAANQADCggICQABNQAECgIIAwABAAAAAA==.Ers:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.',
Et='Etík:BAAANQAECgQIBAAAAA==.',
Ev='Evocative:BAABNQAECoEaAAIKAAkJbR1dBAATAwAKAAkJbR1dBAATAwAAAA==.',
Ex='Exaltso:BAAANQADCgYIDwAAAA==.',
Ey='Eyebright:BAAANQADCgcIBgAAAA==.Eyye:BAAANQADCgQIBgABNQAECgIIBAABAAAAAA==.',
Fa='Farns:BAACNQAFFIEHAAMLAAQJ+iD2AAC0AAACAAMJEyPSCgA8AQALAAIJQRv2AAC0AAA1AAQKgRoAAwIACQkYJRcGAK0DAAIACQnxJBcGAK0DAAsABAkbJqcIAIQBAAAA.Fawndolynn:BAAANQAECgIIAwAAAA==.',
Fe='Felinepriest:BAAANQAECgQIBgAAAA==.Felovan:BAAANQADCgYIBwAAAA==.Felsoaked:BAAANQAECgEIAQAAAA==.Felstehr:BAAANQAECgMIBQAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAAANQAECgcIEwAAAA==.Firebäne:BAAANQAECgUICgAAAA==.Fistnor:BAAANQAECgEIAQAAAA==.',
Fl='Flaminghawk:BAACNQAFFIEFAAICAAMJdhS9DQAKAQACAAMJdhS9DQAKAQA1AAQKgRcAAgIABwk2IcU+AJcCAAIABwk2IcU+AJcCAAAA.',
Fr='Franklin:BAAANQAECgYICAAAAA==.Frankotronic:BAAANQAECgYIDwAAAA==.Freakies:BAAANQADCgQIBgAAAA==.Freyin:BAAANQAECgYIDQAAAA==.Frolgar:BAAANQADCgYICAAAAA==.',
Fu='Fullclangg:BAABNQAECoEXAAIMAAgJdx07FAC+AgAMAAgJdx07FAC+AgABNQAFFAcIEwAIAOwbAA==.Fulldracarys:BAACNQAFFIETAAIIAAcJ7Bt1AACIAgAIAAcJ7Bt1AACIAgA1AAQKgRwAAggACQnPIiADAFADAAgACQnPIiADAFADAAAA.Fullgabagool:BAABNQAECoEWAAINAAgJPBs8JgAiAgANAAgJPBs8JgAiAgABNQAFFAcIEwAIAOwbAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAcIEwAIAOwbAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCggIFwAAAA==.Gaya:BAAANQADCgIIAgAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAAANQAFFAEIAQAAAA==.',
Gl='Glimpse:BAAANQABCgUIBgAAAA==.',
Gn='Gnomebody:BAAANQAECgIIAwAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBgAAAA==.',
Gr='Grimknight:BAABNQAECoEbAAIGAAkJPyb1AgDJAwAGAAkJPyb1AgDJAwAAAA==.',
Gu='Guycow:BAABNQAECoEcAAIMAAkJ9R5fCQAvAwAMAAkJ9R5fCQAvAwAAAA==.',
Ha='Hambonë:BAACNQAFFIEPAAIOAAYJdiDSAABfAgAOAAYJdiDSAABfAgA1AAQKgR0AAg4ACQlnJnoAAPcDAA4ACQlnJnoAAPcDAAAA.Hardballs:BAAANQADCgUIBgAAAA==.Hashbrowns:BAAANQAECgYIDQAAAA==.Havdk:BAEANQAECgIIAwAAAA==.Haxxorwyn:BAAANQAECgYIBwAAAA==.Hazreil:BAAANQAECgYIDgAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIDgAAAA==.Heavenlee:BAAANQAECgMIBQABNQADCggIDgABAAAAAA==.Hecklefish:BAABNQAECoEYAAIPAAgJlSYdBACQAwAPAAgJlSYdBACQAwAAAA==.Hellik:BAAANQABCgMIAwAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAAANQAECgUICQAAAA==.Highdegrees:BAAANQAECgEIAQAAAA==.Hinatta:BAAANQADCggICAABNQAECgQICQABAAAAAA==.Hitagi:BAAANQAECgMICAAAAA==.',
Ho='Hole:BAAANQAECgEIAQAAAA==.Hollo:BAAANQAECgIIAgAAAA==.Holyblasts:BAAANQAECgUIBgAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQABCgMIBAABNQADCgEIAQABAAAAAA==.Horsey:BAAANQAECgYIBwAAAA==.Hownow:BAAANQADCgIIAgAAAA==.',
Hu='Hummingbird:BAAANQADCgUICwABNQAECgUICwABAAAAAA==.Hungus:BAAANQAECgIIAgAAAA==.Hurtszick:BAAANQAECgIIAgAAAA==.',
Hy='Hydrotiger:BAAANQADCgIIAgABNQAECggIGgAQAPYYAA==.',
['Hä']='Härasou:BAAANQADCgYICAAAAA==.',
Il='Illiturtle:BAAANQAECgQICwAAAA==.',
Im='Imnotthtgood:BAAANQADCgYIBgAAAA==.',
In='Indigolemon:BAAANQAECgYIDQABNQAECgcIBwABAAAAAA==.Inkenhancer:BAAANQAECgQICQAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Ja='Jamie:BAAANQAECgYIBgAAAA==.',
Je='Jeynsa:BAAANQADCgUIBwABNQAECgcICQABAAAAAA==.',
Ji='Jingadingado:BAAANQADCgYIBgAAAA==.',
Jo='Jollyollie:BAAANQADCgMIAwAAAA==.Joppy:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQAECgEIAgAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jë']='Jëf:BAAANQADCgIIAgAAAA==.',
['Jô']='Jôker:BAAANQAECgMIBQAAAA==.',
Ka='Kacho:BAAANQAECgEIAQAAAA==.Kaelara:BAAANQAECggIBgAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kappo:BAAANQAECgMIBAAAAA==.Kathorall:BAAANQAECgQICwAAAA==.Kawaiihealer:BAAANQAECgQICQAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIAwAAAA==.Kemper:BAAANQAECgIIBAAAAA==.Kerrs:BAAANQAECgEIAwAAAA==.',
Ki='Kiddyl:BAAANQADCgQIBAAAAA==.Kidneypopper:BAAANQADCgcICAABNQAECgYIDwABAAAAAA==.Kievit:BAAANQAECgYIBwAAAA==.Kir:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Kittana:BAAANQAECgUICQAAAA==.Kittyhawke:BAAANQAECgcIBwAAAA==.',
Kk='Kkelhus:BAAANQAECgEIAQAAAA==.Kkrantuq:BAAANQAECgcIDgAAAA==.Kkylar:BAAANQADCgQIBAAAAA==.',
Kl='Klariityy:BAAANQAECgYIBgAAAA==.Klarity:BAAANQADCgYIBgAAAA==.Klarityx:BAAANQAFFAEIAgAAAA==.',
Kn='Knownentity:BAAANQAECgEIAQAAAA==.',
Ko='Koma:BAAANQADCggICAABNQAFFAQIBgARAL4hAA==.Komatos:BAACNQAFFIEGAAIRAAQJviG1AgCfAQARAAQJviG1AgCfAQA1AAQKgSIAAhEACQllJrIAAPIDABEACQllJrIAAPIDAAAA.Koreantacos:BAAANQADCgcIDQAAAA==.Koronus:BAAANQADCgYIDwAAAA==.',
Kr='Kracklin:BAAANQADCgYIBgAAAA==.',
Ks='Ks:BAAANQADCgMIBgABNQAECgQIBgABAAAAAA==.',
Ku='Kurisutina:BAAANQAECgQICAAAAA==.',
['Kâ']='Kânamë:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.',
['Kê']='Kênsêi:BAAANQAECgYIDgAAAA==.',
['Kô']='Kôan:BAAANQADCgcICQAAAA==.',
La='Lanathel:BAAANQAECgEIAQAAAA==.',
Le='Leafyjoe:BAAANQAECgQICQAAAA==.Legendarybob:BAAANQADCgYIBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAAANQAECgYIDwAAAA==.Legö:BAAANQADCggICgABNQAECgYIDwABAAAAAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.',
Li='Lido:BAAANQAECggICAAAAA==.Lilcowdk:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Lildeemon:BAAANQAECgUIDAAAAA==.Lilspyro:BAAANQAECgMIAwAAAA==.Livathian:BAAANQAECgYIDAAAAA==.',
Lo='Lokrah:BAAANQABCgMIBAAAAA==.',
Lu='Lucifiux:BAAANQAECgEIAQAAAA==.Lunavel:BAAANQAECgYIEgAAAA==.',
Ly='Lydo:BAAANQAECggICwAAAA==.',
Ma='Magicdan:BAAANQADCgYIBwAAAA==.Malnorr:BAAANQAECgQICAAAAA==.Mandragon:BAAANQADCgUIBQABNQAECgkJHAAMAPUeAA==.Mangol:BAAANQAECgcIBwAAAA==.Maryillo:BAACNQAFFIEJAAIOAAYJcBeGAQAbAgAOAAYJcBeGAQAbAgA1AAQKgRwAAg4ACQneJBoFAIgDAA4ACQneJBoFAIgDAAAA.Mattdaemon:BAAANQADCggICAAAAA==.',
Mc='Mcmannis:BAAANQADCggICAAAAA==.Mcpoltrain:BAAANQAECgIIAgAAAA==.',
Me='Mennil:BAAANQADCggIEwAAAA==.Meolater:BAAANQAECgUICwAAAA==.Mesmerise:BAAANQADCgcIEAABNQADCggIDwABAAAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Mindgoblinn:BAAANQAECgMIAwAAAA==.Minyaw:BAAANQADCgcIBwABNQAECgYIEwABAAAAAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQAECgIIAwAAAA==.',
Mm='Mmchocolat:BAAANQADCgIIAgAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEANQAECgYIDgAAAA==.Moolissa:BAAANQAECgQICAAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgEIAwAAAA==.Morbidchaos:BAACNQAFFIEHAAISAAUJphx5AQDoAQASAAUJphx5AQDoAQA1AAQKgR0AAhIACQmlIV4FAFkDABIACQmlIV4FAFkDAAAA.Morkels:BAAANQAECgcIDAABNQAFFAcIEQATAKQdAA==.',
Mu='Muddyshark:BAAANQAECgUICQAAAA==.Mukatsuku:BAAANQAECgQIBQAAAA==.',
My='Mykhawk:BAAANQADCgUICAAAAA==.',
Na='Naeth:BAAANQAECgYIDQAAAA==.Nalrot:BAAANQADCggIDwAAAA==.Narcine:BAAANQAECgYIBgAAAA==.',
Ne='Neciecakes:BAAANQAECgYIDgAAAA==.Nee:BAABNQAECoEcAAMUAAkJpBFFJQA5AgAUAAkJpBFFJQA5AgARAAQJPBBVagAOAQAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nekus:BAAANQADCgcIBwAAAA==.Nelor:BAAANQAECgQIBwAAAA==.Neverheal:BAAANQADCgEIAQAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ng='Ngàymai:BAAANQADCgQIBAAAAA==.',
Ni='Nightwatchr:BAAANQAECgMIAwAAAA==.Nisona:BAAANQADCgcIEwAAAA==.Nitashal:BAABNQAECoEYAAMIAAkJch0LBgD/AgAIAAkJch0LBgD/AgAKAAEJoA57KAA2AAAAAA==.',
No='Noremac:BAAANQADCgYIDAAAAA==.',
Nu='Nubsaiboot:BAAANQAECgMIAwABNQAECgMIBAABAAAAAA==.',
Ny='Nythariel:BAAANQADCggIEwAAAA==.',
Od='Odi:BAAANQADCgcIGQAAAA==.',
Ok='Okiaat:BAAANQADCgIIAgAAAA==.',
Ol='Oliviawildè:BAAANQAECgcICgAAAA==.',
On='Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAAANQAECgYIDgAAAA==.Pallyforhire:BAAANQADCgYIEAAAAA==.Pantyblossom:BAAANQAECgMIBAAAAA==.',
Pe='Peaches:BAAANQAECgQIBgAAAA==.Peewees:BAAANQADCgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAAANQAECgUIDQAAAA==.Pelito:BAAANQABCgQIAgAAAA==.Pell:BAAANQABCgIIAgAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQADCgYIEQABNQAECgYIDQABAAAAAA==.',
Ph='Phaeddrus:BAAANQAECgQIBQAAAA==.Phrix:BAAANQADCgYIBgABNQAECggIGQAKAH0aAA==.',
Pi='Pinecone:BAABNQAECoEbAAIOAAkJbSPeBwBdAwAOAAkJbSPeBwBdAwAAAA==.',
Pl='Ploppster:BAAANQADCggICAAAAA==.Plot:BAAANQAECgEIAQAAAA==.',
Po='Poekimaw:BAAANQAECgEIAQAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAABNQAECoEZAAIGAAkJiyXzAgDKAwAGAAkJiyXzAgDKAwAAAA==.Poppinin:BAAANQAECgQIBQAAAA==.Potaters:BAAANQADCgQIBAAAAA==.Potshotbot:BAAANQADCgYIBgAAAA==.Powerwordhug:BAAANQAECgQIBgABNQAECgUICgABAAAAAA==.',
Pr='Praedo:BAAANQADCgYIBgAAAA==.Prevaleon:BAAANQADCgIIAQAAAA==.',
Ps='Psychaos:BAAANQADCgUIBQAAAA==.Psychostorm:BAAANQAECgEIAQAAAA==.Psychritic:BAAANQAECgcIDAAAAA==.Psyence:BAAANQADCgYIDQAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purrsnikitty:BAAANQADCggIDgAAAA==.Pus:BAAANQADCgYIBgAAAA==.',
Qu='Quillmane:BAAANQADCggIFgABNQAECggIGQAKAH0aAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAAANQAECgcIDwAAAA==.Ragingdeath:BAAANQADCgEIAQAAAA==.Rainakamugi:BAAANQAECgMIAwABNQAECgkJFwANAKgTAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQADCggIGwAAAA==.Ralphanir:BAAANQAECgMIBQAAAA==.Raskreia:BAAANQADCggICQAAAA==.Raygyu:BAAANQADCgQIBAABNQAFFAEIAQABAAAAAA==.Rayvoker:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Re='Reek:BAAANQAECgQICAAAAA==.Rexari:BAAANQAECgQICQAAAA==.Rezmae:BAAANQAECgEIAgAAAA==.',
Ri='Riniedaze:BAAANQADCgUICgAAAA==.',
Ro='Rockandstone:BAABNQAECoEfAAIMAAkJlxM2GQCWAgAMAAkJlxM2GQCWAgAAAA==.Rooty:BAAANQAECgEIAQAAAA==.',
Sa='Safetyspork:BAAANQAECgIIBAAAAA==.Sagë:BAAANQAECgUIBwAAAA==.Sakonutz:BAAANQAECgUIBwAAAA==.Salsa:BAAANQADCgYIBgAAAA==.Saresh:BAAANQADCgcIBwAAAA==.Sathariel:BAAANQABCgIIAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.',
Sc='Screeps:BAAANQABCgcIDgABNQADCgEIAQABAAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAAANQAECgMIBAABNQAECgMIBAABAAAAAA==.Sendh:BAAANQAECgQIBAAAAA==.Sermet:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Sermonn:BAAANQAECgEIAQAAAA==.Serous:BAAANQAECgIIAgAAAA==.Seshin:BAAANQAECggIGwAAAQ==.Setal:BAABNQAECoEZAAIKAAgJfRp2CACMAgAKAAgJfRp2CACMAgAAAA==.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgYIEwABAAAAAA==.Shammoo:BAAANQADCgEIAQAAAA==.Shcho:BAAANQADCgMIAwAAAA==.Sheepe:BAAANQAECgIIAgAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgQIBAAAAA==.Shinyscalp:BAAANQAECgQIBQAAAA==.Shogunz:BAAANQAECgEIAQAAAA==.',
Si='Simaria:BAAANQADCgYIDAAAAA==.Sinapaladin:BAAANQAECgMIBAAAAA==.Siomara:BAAANQAECgUIBQAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgEIAQAAAA==.',
Sl='Slabbster:BAAANQAECgQIBQAAAA==.',
Sm='Smooshednewt:BAABNQAECoEaAAIQAAgJ9hidBgChAgAQAAgJ9hidBgChAgAAAA==.',
Sn='Sne:BAAANQAECgQIBAAAAA==.Snoop:BAAANQAECgEIAQAAAA==.',
So='Soloa:BAAANQAECgIIAgAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAAANQAECgYIEQABNQAECgcICQABAAAAAA==.Sosneaky:BAAANQADCgMICAAAAA==.Soulfuria:BAAANQAECgcIBwAAAA==.',
Sp='Spekk:BAAANQADCgYICgAAAA==.Speknawz:BAAANQAECgcIEAAAAA==.Splatzill:BAAANQADCgIIAgABNQAECgcIEwABAAAAAA==.Spoiledangel:BAAANQAECgMIBQAAAA==.Spoonhat:BAAANQADCgYICgABNQAECgIIBAABAAAAAA==.Springz:BAAANQAECgUICAAAAA==.',
St='Staggering:BAAANQAECgYICgAAAA==.Starryniight:BAAANQADCggIDgAAAA==.Stephsux:BAAANQAECgUIBwAAAA==.Stickers:BAAANQAECgEIAQAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgEIAQAAAA==.Suika:BAAANQAECgQIBAAAAA==.Supanova:BAAANQAECgQICgABNQAECggIGgAQAPYYAA==.',
Sv='Svelus:BAABNQAECoEcAAIGAAkJZCUABAC3AwAGAAkJZCUABAC3AwAAAA==.',
Sw='Swingin:BAAANQAECgQICQAAAA==.',
Sy='Sycophancy:BAAANQADCgQIBAAAAA==.Synaptichole:BAAANQADCggIGwAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tanurhide:BAAANQADCgQIBAAAAA==.Tartan:BAAANQAECgQIBQAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.',
Te='Techi:BAAANQADCgIIAgAAAA==.Teewat:BAAANQADCgUIBQAAAA==.Temres:BAAANQAECgQIBAAAAA==.Tendermulva:BAAANQAECgUICQAAAA==.Terekk:BAAANQADCgUICAAAAA==.Teshtara:BAAANQADCgYIBgABNQAECgcICQABAAAAAA==.',
Th='Theod:BAAANQADCgYIBwAAAA==.Thesauce:BAABNQAECoEcAAMVAAkJVSQZAgCaAwAVAAkJFyQZAgCaAwAWAAQJZCHUDACIAQAAAA==.Thimo:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Thrikal:BAAANQAECgYIDgAAAA==.',
To='Tomsmg:BAAANQAECgYIDgAAAA==.Toofs:BAAANQAECgMIBAAAAA==.Toxifay:BAAANQAECgQIBAAAAA==.',
Tr='Traell:BAAANQADCgYIDAABNQAECgYIDgABAAAAAA==.Treehuggles:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Truedat:BAAANQADCgQIBwAAAA==.',
Ug='Ughtismo:BAAANQADCgUIBQAAAA==.',
Us='Usagiknight:BAAANQAECgYICgAAAA==.Ushii:BAAANQAECgQIBgAAAA==.',
Va='Valdemort:BAAANQADCgQIBAABNQAECgIIBAABAAAAAA==.Valei:BAAANQAECgMIAwAAAA==.',
Ve='Veganforlife:BAAANQADCgIIAwAAAA==.',
Vi='Vinda:BAAANQAECgYIDgAAAA==.Vivixia:BAAANQAECgYICQAAAA==.',
Vo='Voodoolock:BAAANQAECgQIBgAAAA==.',
Wa='Walkingboot:BAAANQADCgQIBAAAAA==.Wallo:BAAANQAECgYIDQAAAA==.Washedbolt:BAAANQADCgYIBgAAAA==.Washedpyro:BAAANQADCgYICwAAAA==.Washedzebu:BAAANQAECgYIEgAAAA==.Wayfairkid:BAAANQAECgEIAQAAAA==.',
We='Weeb:BAACNQAFFIERAAITAAcJpB0dAAC9AgATAAcJpB0dAAC9AgA1AAQKgR8AAxMACQlIJksAAMgDABMACQlIJksAAMgDAAoACAmQGmALADwCAAAA.',
Wh='Whiterabbitt:BAAANQADCggIHAAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQADCggIDAAAAA==.Wilmabfiymr:BAAANQAECgEIAQAAAA==.',
Wo='Woa:BAAANQADCggIEgAAAA==.Woofwoofwoof:BAAANQAECgEIAQAAAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Xi='Xiolan:BAAANQAECgQIBQABNQAECggIGgAGAFcfAA==.',
Ye='Yeeloow:BAAANQADCgYICAAAAA==.',
Ys='Yshaarj:BAAANQADCggIEgAAAA==.',
Yu='Yulok:BAABNQAECoEaAAIWAAkJkyY4AAD1AwAWAAkJkyY4AAD1AwAAAA==.Yuukí:BAAANQADCggICAABNQAECggIGgAGAFcfAA==.',
Za='Zaberra:BAAANQAECgcICQAAAA==.Zanarkand:BAAANQAECgMIAwAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zexexe:BAAANQAECgcIDQABNQAFFAYIDwAOAHYgAA==.',
Zi='Zibroth:BAAANQAECgQICQAAAA==.Zieg:BAAANQAECgUIBQABNQAECggIDwAKACMUAA==.Zina:BAAANQAECgIIAgAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQADCggICAAAAA==.',
['Ýu']='Ýuuki:BAABNQAECoEaAAIGAAgJVx+ZGwDEAgAGAAgJVx+ZGwDEAgAAAA==.',
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
